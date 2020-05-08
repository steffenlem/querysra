#!/usr/bin/env nextflow
/*
========================================================================================
                         steffenlem/querysra
========================================================================================
 steffenlem/querysra Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/steffenlem/querysra
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info """

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run steffenlem/querysra --keywords path/to/keywordlist -profile docker

    Mandatory arguments:
      --preselection                List of broad keywords to initially search the SRA database
      --blacklist                   List of keywords that are note allowed to be in the sample description
      --classes_keywords            JSON file containing the classes and the respective keywords
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Optional arguments:
      --sradb                       SRAdb SQLite file (https://s3.amazonaws.com/starbuck1/sradb/SRAmetadb.sqlite.gz)
      --taxon_id                    Taxon ID of the samples
      --library_strategy            Library strategy of the sample
      --ncbi_api_key                NCBI API key needed to perform requests
      
    Options:
      --get_access_status           determine which samples/projects are publicly available or under controlled access

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail               Same as --email, except only send mail if the workflow is not successful
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}

if (workflow.profile == 'awsbatch') {
    // AWSBatch sanity checking
    if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
    // Check outdir paths to be S3 buckets if running on AWSBatch
    // related: https://github.com/nextflow-io/nextflow/issues/813
    if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
    // Prevent trace files to be stored on S3 since S3 does not support rolling files.
    if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

/*
 * Create a channel for input read files
 */
params.sradb = 'NO_FILE'
sradb_file = file(params.sradb)
params.taxon_id = '9606' // human is default
params.library_strategy = 'RNA-Seq'

//Channel.fromPath("${params.preselection}")
//        .ifEmpty { exit 1, "Please provide a file containing keywords to search the SRA database" }
//        .set { keyword_channel }

if (!params.preselection || params.preselection == true) {
    exit 1, "Please provide a file containing keywords to search the SRA database"
}
else{
    Channel.fromPath("${params.preselection}", checkIfExists: true)
            .ifEmpty { exit 1, "Please provide a file containing keywords to search the SRA database" }
            .set { keyword_channel }
}

if (!params.blacklist || params.blacklist == true) {
    exit 1, "No file with keywords to exclude samples from the output was specified"
}
else{
    Channel.fromPath("${params.blacklist}", checkIfExists: true)
            .ifEmpty { exit 1, "No file with keywords to exclude samples from the output was specified" }
            .set { blacklist_file }
}

if (!params.classes_keywords || params.classes_keywords == true){
    exit 1, "Please provide the path to the file containing the classes and keywords"
}
else {
    Channel.fromPath("${params.classes_keywords}", checkIfExists: true)
            .ifEmpty { exit 1, "Please provide the path to the file containing the classes and keywords" }
            .set { classes_keywords_file }
}

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name'] = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['Keywords'] = params.keywords
summary['Max Resources'] = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir'] = params.outdir
summary['Launch dir'] = workflow.launchDir
summary['Working dir'] = workflow.workDir
summary['Script dir'] = workflow.projectDir
summary['User'] = workflow.userName
if (workflow.profile == 'awsbatch') {
    summary['AWS Region'] = params.awsregion
    summary['AWS Queue'] = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact) summary['Config Contact'] = params.config_profile_contact
if (params.config_profile_url) summary['Config URL'] = params.config_profile_url
if (params.email || params.email_on_fail) {
    summary['E-mail Address'] = params.email
    summary['E-mail on failure'] = params.email_on_fail
}
log.info summary.collect { k, v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text = """
    id: 'nf-core-querysra-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'steffenlem/querysra Workflow Summary'
    section_href: 'https://github.com/steffenlem/querysra'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k, v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

    return yaml_file
}

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
            saveAs: { filename ->
                if (filename.indexOf(".csv") > 0) filename
                else null
            }

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml
    file "software_versions.csv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    echo \$(R --version 2>&1) > v_R.txt
    echo \$(python --version 2>&1) > v_python.txt
    echo \$(pip freeze | grep Click 2>&1) > v_click.txt
    Rscript -e "library(argparse); write(x=as.character(packageVersion('argparse')), file='v_argparse.txt')"
    Rscript -e "library(SRAdb); write(x=as.character(packageVersion('SRAdb')), file='v_SRAdb.txt')"
    Rscript -e "library(stringr); write(x=as.character(packageVersion('stringr')), file='v_stringr.txt')"
    scrape_software_versions.py > software_versions_mqc.yaml
    """
}

println blacklist_file

/*
 * STEP 1 - SRAdb querying
 */
process SRAdb {
    publishDir "${params.outdir}/SRAdb", mode: 'copy'

    input:
    file(keyword_file) from keyword_channel
    file(database_file) from sradb_file

    output:
    file "prefiltering.tsv" into prefiltered_runs

    script:
    def sradb = database_file != 'NO_FILE' ? "-db $database_file" : ''
    """
    query_sra.R -k $keyword_file $sradb -t $params.taxon_id -l $params.library_strategy 
    """
}


/*
 * STEP 2 - Keyword filtering
 */
process keyword_filtering {
    publishDir "${params.outdir}/keyword_filtering", mode: 'copy'

    input:
    file(filtered_sra) from prefiltered_runs
    file(blacklist) from blacklist_file
    file(classes_keywords_list) from classes_keywords_file

    output:
    file "*" into outfiles

    script:

    def get_access_status_param = params.get_access_status ? "--get_access_status" : ''
    def ncbi_api_key_param = params.ncbi_api_key ? "--ncbi_api_key $params.ncbi_api_key" : ''

    """
    sra_filtering.py -i $filtered_sra -o . -b $blacklist -k  $classes_keywords_list $get_access_status_param $ncbi_api_key_param
    """
}


/*
 * STEP 3 - Output Description HTML
 */
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs


    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.py $output_docs -o results_description.html
    """
}

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[steffenlem/querysra] Successful: $workflow.runName"
    if (!workflow.success) {
        subject = "[steffenlem/querysra] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if (workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp


    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir"]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
            if (params.plaintext_email) {
                throw GroovyException('Send plaintext e-mail, not HTML')
            }
            // Try to send HTML e-mail using sendmail
            ['sendmail', '-t'].execute() << sendmail_html
            log.info "[steffenlem/querysra] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
            // Catch failures and try with plaintext
            ['mail', '-s', subject, email_address].execute() << email_txt
            log.info "[steffenlem/querysra] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File("${params.outdir}/pipeline_info/")
    if (!output_d.exists()) {
        output_d.mkdirs()
    }
    def output_hf = new File(output_d, "pipeline_report.html")
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File(output_d, "pipeline_report.txt")
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
        log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
        log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}"
        log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}"
    }

    if (workflow.success) {
        log.info "${c_purple}[steffenlem/querysra]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[steffenlem/querysra]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader() {
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  steffenlem/querysra v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
