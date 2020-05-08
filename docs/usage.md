# steffenlem/querysra: Usage

## Table of contents

* [Table of contents](#table-of-contents)
* [Introduction](#introduction)
* [Running the pipeline](#running-the-pipeline)
  * [Updating the pipeline](#updating-the-pipeline)
  * [Reproducibility](#reproducibility)
* [Main arguments](#main-arguments)
  * [`-profile`](#-profile)
  * [`--preselection`](#--preselection)
  * [`--blacklist`](#--blacklist)
  * [`--classes_keywords`](#--classes_keywords)
  * [`--sradb`](#--sradb)
  * [`--taxon_id`](#--taxon_id)
  * [`--library_strategy`](#--library_strategy)
  * [`--get_access_status`](#--get_access_status)
  * [`--ncbi_api_key`](#--ncbi_api_key)
* [Job resources](#job-resources)
  * [Automatic resubmission](#automatic-resubmission)
  * [Custom resource requests](#custom-resource-requests)
* [AWS Batch specific parameters](#aws-batch-specific-parameters)
  * [`--awsqueue`](#--awsqueue)
  * [`--awsregion`](#--awsregion)
  * [`--awscli`](#--awscli)
* [Other command line parameters](#other-command-line-parameters)
  * [`--outdir`](#--outdir)
  * [`--email`](#--email)
  * [`--email_on_fail`](#--email_on_fail)
  * [`-name`](#-name)
  * [`-resume`](#-resume)
  * [`-c`](#-c)
  * [`--custom_config_version`](#--custom_config_version)
  * [`--custom_config_base`](#--custom_config_base)
  * [`--max_memory`](#--max_memory)
  * [`--max_time`](#--max_time)
  * [`--max_cpus`](#--max_cpus)
  * [`--plaintext_email`](#--plaintext_email)
  * [`--monochrome_logs`](#--monochrome_logs)

## Introduction

Nextflow handles job submissions on SLURM or other environments, and supervises running the jobs. Thus the Nextflow process must run until the pipeline is finished. We recommend that you put the process running in the background through `screen` / `tmux` or similar tool. Alternatively you can run nextflow within a cluster job submitted your job scheduler.

It is recommended to limit the Nextflow Java virtual machines memory. We recommend adding the following line to your environment (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```

<!-- TODO nf-core: Document required command line parameters to run the pipeline-->

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run steffenlem/querysra --reads '*_R{1,2}.fastq.gz' -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work            # Directory containing the nextflow working files
results         # Finished results (configurable, see below)
.nextflow_log   # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull steffenlem/querysra
```

### Reproducibility

It's a good idea to specify a pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [steffenlem/querysra releases page](https://github.com/steffenlem/querysra/releases) and find the latest version number - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future.

## Main arguments

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Conda) - see below.

> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended.

* `docker`
  * A generic configuration profile to be used with [Docker](http://docker.com/)
  * Pulls software from dockerhub: [`steffenlem/querysra`](http://hub.docker.com/r/steffenlem/querysra/)
* `singularity`
  * A generic configuration profile to be used with [Singularity](http://singularity.lbl.gov/)
  * Pulls software from DockerHub: [`steffenlem/querysra`](http://hub.docker.com/r/steffenlem/querysra/)
* `conda`
  * Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker or Singularity.
  * A generic configuration profile to be used with [Conda](https://conda.io/docs/)
  * Pulls most software from [Bioconda](https://bioconda.github.io/)
* `test`
  * A profile with a complete configuration for automated testing
  * Includes links to test data so needs no other parameters

<!-- TODO nf-core: Document required command line parameters -->

### `--preselection`

A newline-separated file of keywords to initially search the complete SRA database. For example:
```bash
--preselection some_file.txt
```

### `--blacklist`

A newline-separated file of keywords that are not allowed to be included in the samples' description of the final output. 
```bash
--blacklist some_file.txt
```

### `--classes_keywords`

JSON file defining one or more groups of samples in the output. For each group/class, a list of keywords is defined that identify samples for the respective class. 
```bash
--classes_keywords some_file.txt
```

### `--sradb`

This parameter allows providing an SRAmetadb sqlite database file, which contains all the metadata information of samples in SRA. For example:
```bash
--classes_keywords some_file.txt
```
If no file is not provided, the database file is downloaded automatically (~2 GB). However, it can be advantageous to download the file and provide it to the pipeline manually, if multiple reruns are performed.
The file can be obtained here:
https://s3.amazonaws.com/starbuck1/sradb/SRAmetadb.sqlite.gz

### `--taxon_id`

Use this to specify the NCBI taxonomy ID of the samples to search:
e.g.: Homo sapiens 9606; Mus Musculus 10090

```bash
--taxon_id 9606
```

### `--library_strategy`

Use this to specify the library strategy of the samples to search:
e.g.: RNA-Seq, WGS, WXS, ChIP-Seq
More information about the different library strategies can be found here:
https://www.ebi.ac.uk/ena/submit/reads-library-strategy

```bash
--blacklist some_file.txt
```

### `--get_access_status`

Set this flag to check the access status for each sample (either public or dbGAP protected). To check the status, an NCBI api key is needed.

```bash
--get_access_status 
```

### `--ncbi_api_key`

This argument is used to provide an NCBI API key. The key can be obtained from the NCBI website (Info: https://ncbiinsights.ncbi.nlm.nih.gov/2017/11/02/new-api-keys-for-the-e-utilities/). 

```bash
--ncbi_api_key ncbi_key 
```

## Job resources

### Automatic resubmission

Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the steps in the pipeline, if the job exits with an error code of `143` (exceeded requested resources) it will automatically resubmit with higher requests (2 x original, then 3 x original). If it still fails after three times then the pipeline is stopped.

## AWS Batch specific parameters

Running the pipeline on AWS Batch requires a couple of specific parameters to be set according to your AWS Batch configuration. Please use [`-profile awsbatch`](https://github.com/nf-core/configs/blob/master/conf/awsbatch.config) and then specify all of the following parameters.

### `--awsqueue`

The JobQueue that you intend to use on AWS Batch.

### `--awsregion`

The AWS region in which to run your job. Default is set to `eu-west-1` but can be adjusted to your needs.

### `--awscli`

The [AWS CLI](https://www.nextflow.io/docs/latest/awscloud.html#aws-cli-installation) path in your custom AMI. Default: `/home/ec2-user/miniconda/bin/aws`.

Please make sure to also set the `-w/--work-dir` and `--outdir` parameters to a S3 storage bucket of your choice - you'll get an error message notifying you if you didn't.

## Other command line parameters

<!-- TODO nf-core: Describe any other command line flags here -->

### `--outdir`

The output directory where the results will be saved.

### `--email`

Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits. If set in your user config file (`~/.nextflow/config`) then you don't need to specify this on the command line for every run.

### `--email_on_fail`

This works exactly as with `--email`, except emails are only sent if the workflow is not successful.

### `-name`

Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

**NB:** Single hyphen (core Nextflow option)

### `-resume`

Specify this when restarting a pipeline. Nextflow will used cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously.

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

**NB:** Single hyphen (core Nextflow option)

### `-c`

Specify the path to a specific config file (this is a core NextFlow command).

**NB:** Single hyphen (core Nextflow option)

Note - you can use this to override pipeline defaults.

### `--custom_config_version`

Provide git commit id for custom Institutional configs hosted at `nf-core/configs`. This was implemented for reproducibility purposes. Default: `master`.

```bash
## Download and use config file with following git commid id
--custom_config_version d52db660777c4bf36546ddb188ec530c3ada1b96
```

### `--custom_config_base`

If you're running offline, nextflow will not be able to fetch the institutional config files
from the internet. If you don't need them, then this is not a problem. If you do need them,
you should download the files from the repo and tell nextflow where to find them with the
`custom_config_base` option. For example:

```bash
## Download and unzip the config files
cd /path/to/my/configs
wget https://github.com/nf-core/configs/archive/master.zip
unzip master.zip

## Run the pipeline
cd /path/to/my/data
nextflow run /path/to/pipeline/ --custom_config_base /path/to/my/configs/configs-master/
```

> Note that the nf-core/tools helper package has a `download` command to download all required pipeline
> files + singularity containers + institutional configs in one go for you, to make this process easier.

### `--max_memory`

Use to set a top-limit for the default memory requirement for each process.
Should be a string in the format integer-unit. eg. `--max_memory '8.GB'`

### `--max_time`

Use to set a top-limit for the default time requirement for each process.
Should be a string in the format integer-unit. eg. `--max_time '2.h'`

### `--max_cpus`

Use to set a top-limit for the default CPU requirement for each process.
Should be a string in the format integer-unit. eg. `--max_cpus 1`

### `--plaintext_email`

Set to receive plain-text e-mails instead of HTML formatted.

### `--monochrome_logs`

Set to disable colourful command line output and live life in monochrome.
