#!/usr/bin/env python
import click
import sys
import time
import logging
import json
from collections import Counter
import urllib3
import xmltodict
import time
import os

urllib3.disable_warnings()

console = logging.StreamHandler()
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
console.setFormatter(formatter)
LOG = logging.getLogger("Filter SRA query output")
LOG.addHandler(console)
LOG.setLevel(logging.INFO)


@click.command()
@click.option('-i', '--inputpath',
              help='Path to tsv containing the subset of SRA to filter. The file has the format of the SRA relation of'
                   'the meta-database of SRA', required=True)
@click.option('-o', '--outputdir',
              help='Output directory',
              required=True, default=".")
@click.option('-b', '--blacklist',
              help='list of general keywords that identify runs to be excluded',
              required=True)
@click.option('-k', '--keyword_list', help='JSON file containing the defining keywords for each class', required=True)
@click.option('-n', '--ncbi_api_key', help='NCBI api key for submitting requests', required=False)
@click.option('--get_access_status', is_flag=True)
def main(inputpath, outputdir, blacklist, keyword_list, ncbi_api_key, get_access_status):
    # start timer
    start = time.time()

    LOG.info("Parse SRA query output file")
    sra_relation, col_names = parse_sra_relation(inputpath)

    LOG.info("Parse keyword lists")
    blacklist_keywords = parse_keyword_list(blacklist)

    # all_class_names = []
    # all_class_keywords = []
    # for single_list in keyword_list:
    #     all_class_names.append(
    #         single_list.split(".")[0].split("/")[-1])  # class name is set to the name of the keyword file
    #     all_class_keywords.append(parse_keyword_list(single_list))

    all_class_keywords, all_class_names = parse_keyword_json(keyword_list)

    LOG.info("Filter samples")
    fields_to_search = ["sample_attribute",
                        "experiment_title",
                        "sample_name"]  # all other possible fields are specified in col_names TODO parameter for specification during input

    excluded_runs, included_runs = filter_samples(sra_relation, col_names, fields_to_search, blacklist_keywords)

    LOG.info("Classify samples")
    classified_runs, unresolved_runs, undefined_runs = classify_runs(included_runs, col_names, fields_to_search,
                                                                     all_class_keywords)

    if get_access_status:
        if ncbi_api_key:
            LOG.info("Get access status of the NCBI website")

            classified_runs, all_class_names = check_access_status(classified_runs, all_class_names, ncbi_api_key)
        else:
            exit("Error: Please provide an NCBI API Key")

    LOG.info("Generate output files")
    idx_fields_to_write = [col_names.index(field) for field in
                           ["run_accession", "sample_attribute", "sample_name", "experiment_title", "study_accession"]]

    for run_class, class_name in zip(classified_runs, all_class_names):
        write_run_subset_to_file(run_class, col_names, idx_fields_to_write.copy(), class_name + "_", all_class_names,
                                 outputdir)

    write_run_subset_to_file(undefined_runs, col_names, idx_fields_to_write.copy(), "undefined_", all_class_names,
                             outputdir)
    write_run_subset_to_file(unresolved_runs, col_names, idx_fields_to_write.copy(), "unresolved_", all_class_names,
                             outputdir)

    LOG.info("Generate project summary")
    generate_project_overview(classified_runs, col_names, all_class_names, outputdir)

    LOG.info("Generate download list")
    generate_download_list(classified_runs, all_class_names, col_names, outputdir)

    # stop timer
    end = time.time()
    LOG.info("Process finished in " + str(round(end - start, 2)) + " sec")

    return 0


def parse_sra_relation(inputpath):
    """
    Parse tsv file of the SRA relation of SRAmetadb.sqlite

    :param inputpath: path to file
    :return: 2D array of the parsed relation, name of the columns
    """
    sra_relation = []
    with open(inputpath, "r") as file:
        col_names = [cell.replace('"', '') for cell in next(file).split("\n")[0].split("\t")]
        for line in file:
            splitted = [cell.replace('"', '') for cell in line.split("\n")[0].split("\t")]
            sra_relation.append(splitted)
    return sra_relation, col_names


def parse_keyword_list(keyword_file):
    """
    :param keyword_file: "\n" separated keyword file
    :return: list of keyword strings
    """
    keywords = []
    with open(keyword_file, "r") as file:
        for line in file:
            parsed_word = line.split("\n")[0]
            if not parsed_word == "":
                keywords.append(parsed_word)
    return keywords


def is_key_in_run(run, idx_fields_to_search, keyword_list):
    """
    search information of a sra run for a list of keywords

    :param run: fields with run information
    :param idx_fields_to_search: indices of fields in which to search for the keywords
    :param keyword_list: list of keyword Strings
    :return: boolean, first identified keyword String
    """
    for idx in idx_fields_to_search:
        for keyword in keyword_list:
            if keyword.lower() in run[idx].lower():
                return True, keyword
    return False, ""


def filter_samples(sra_relation, col_names, fields_to_search, blacklist):
    """
    filter out runs which contain keyword Strings defined in the blacklist

    :param sra_relation: parsed sra_relation (2D array)
    :param col_names: names of columns of the sra_relation
    :param fields_to_search: column names of the fields to search
    :param blacklist: list of keywords which are not allowed to be contain in the run information
    :return: list of excluded runs (contain blacklist keywords), list of runs which passed the filtering step
    """
    excluded_runs = []
    included_runs = []
    idx_fields_to_search = [col_names.index(field) for field in fields_to_search]
    for run in sra_relation:
        is_in_blacklist, keyword_b = is_key_in_run(run, idx_fields_to_search, blacklist)
        if is_in_blacklist:
            excluded_runs.append(run)
        else:
            included_runs.append(run)
    return excluded_runs, included_runs


def classify_runs(runs, col_names, fields_to_search, list_of_keyword_lists):
    """
    Classify runs according to the provided keyword lists

    :param runs: list of blacklist filtered runs
    :param col_names: names of columns of the sra_relation
    :param fields_to_search: column names of the fields to search
    :param list_of_keyword_lists: nested list of keywords, each item is a list of keywords for one class
    :return: nested list of classifed runs, list of runs which are part of at least two classes (unresolved), list of runs which could not be classified
    """
    classified_runs = [[] for x in list_of_keyword_lists]  # nested list; each item is a list for a specific class
    unresolved_runs = []
    undefined_runs = []
    idx_fields_to_search = [col_names.index(field) for field in fields_to_search]
    for run in runs:
        part_of_class_overview = []  # contains one boolean for each list of keywords (True -> run part of class, False --> run not part of class)
        for keywords_class_list in list_of_keyword_lists:
            is_part_of_class, class_key = is_key_in_run(run, idx_fields_to_search, keywords_class_list)
            run = run + [class_key]  # add identified key to list information of the run
            part_of_class_overview.append(is_part_of_class)

        # find number of True items; 0 -> undefined; 1 -> search for class; > 2 -> unresolved
        if part_of_class_overview.count(True) == 0:  # zero class matches for run
            undefined_runs.append(run)
        elif part_of_class_overview.count(True) > 1:  # more than one class matches for run
            unresolved_runs.append(run)
        else:  # exactly one class for run  --> identify class and add to respective sublist
            classified_runs[part_of_class_overview.index(True)].append(run)

    return classified_runs, unresolved_runs, undefined_runs


def write_run_subset_to_file(runs, col_names, idx_fields_to_search, prefix, all_class_names, outputdir):
    """
    write list (classified runs) to file. Write only relevant columns to file

    :param runs: list of classified runs
    :param col_names: names of columns of the sra_relation
    :param idx_fields_to_search: indices of the fields to search
    :param prefix: prefix for the outputfile
    :param all_class_names: names for each class
    :param outputdir: output directory
    :return: None
    """
    if not os.path.isdir(outputdir + '/sample_overview'):
        os.mkdir(outputdir + '/sample_overview')

    col_names = [col_names[i] for i in idx_fields_to_search]
    idx_fields_to_search += [i * -1 for i in reversed(range(1, len(all_class_names) + 1))]
    with open(outputdir + '/sample_overview' + "/" + prefix + "samples.tsv", "w") as file:
        file.write(
            "\t".join(col_names) + "\t" + "\t".join([name + "_identified_keyword" for name in all_class_names]) + "\n")
        for run in runs:
            run = [run[i] for i in idx_fields_to_search]
            file.write("\t".join(run) + "\n")


def generate_project_overview(classified_runs, col_names, all_class_names, outputdir):
    """
    Generate an overview about the classified runs

    :param classified_runs: list of runs
    :param col_names: names of columns of the sra_relation
    :param all_class_names: names for each class
    :param outputdir: output directory
    :return: None
    """
    if not os.path.isdir(outputdir + '/summary_statistics'):
        os.mkdir(outputdir + '/summary_statistics')

    idx_study_acc = col_names.index("study_accession")
    for class_runs, class_name in zip(classified_runs, all_class_names):
        project_ids_single = []
        for run in class_runs:
            project_ids_single.append(run[idx_study_acc])
        write_summary_statistic_runs(project_ids_single,
                                     outputdir + '/summary_statistics' + "/" + class_name + "_summary_samples.txt")


def write_summary_statistic_runs(ids, outputdir):
    """
    Write a text file containing total number of projects, total number of runs and the number of runs for each project
    :param ids: list of runs
    :param outputdir: output directory
    :return: None
    """
    if len(ids) != 0:
        labels, values = zip(*Counter(ids).items())
        values, labels = zip(*sorted(zip(values, labels), reverse=True))
        number_of_projects = len(labels)
        number_of_samples = sum(values)
    else:  # no samples were identified for the class + A
        number_of_projects = 0
        number_of_samples = 0
        labels = values = []
    with open(outputdir, "w") as file:
        file.write("# of runs:\t" + str(number_of_samples) + "\n")
        file.write("# of projects:\t" + str(number_of_projects) + "\n\n")
        for project, count in zip(labels, values):
            file.write(project + "\t" + str(count) + "\n")


def generate_download_list(classified_runs, all_class_names, col_names, outputdir):
    """
    Write list of run_ids to file
    :param classified_runs: list of runs
    :param all_class_names: names for each class
    :param col_names: names of columns of the sra_relation
    :param outputdir: output directory
    :return:
    """
    idx_run_acc = col_names.index("run_accession")

    if not os.path.isdir(outputdir + '/download_lists'):
        os.mkdir(outputdir + '/download_lists')

    for i in range(len(classified_runs)):
        run_accessions = []
        for run in classified_runs[i]:
            run_accessions.append(run[idx_run_acc])

        with open(outputdir + '/download_lists' + "/" + all_class_names[i] + "_dl_list.txt", "w") as file:
            for run_id in run_accessions:
                file.write(run_id + "\n")


def parse_keyword_json(keyword_list):
    all_class_keywords = []
    with open(keyword_list, 'r') as f:
        datastore = json.load(f)
        all_class_names = list(datastore.keys())
        for class_name in all_class_names:
            all_class_keywords.append(list(datastore[class_name]))
    return all_class_keywords, all_class_names


def summary_statistic_bases(healthy_runs, tumor_runs, unresolved_runs, undefined_runs, outputdir):
    return 0


def get_id_from_accn(accn, api_key):
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term="
    # api_key = "702f4a3b99c88a65efe86d822642e3900208"
    suffix_url = "&api_key="

    url = base_url + accn + suffix_url + api_key
    http = urllib3.PoolManager()
    response = http.request('GET', url)

    try:
        data = xmltodict.parse(response.data)
    except IOError:
        print("ID getter: Failed to parse xml from response")
    try:
        id = data['eSearchResult']['IdList']['Id']
    except:
        print("ID couldn't be extracted (%s)" % accn)
        id = "-1"

    return id


def get_access_info(id, accn, api_key):
    if id == "-1":
        return "", "", ""

    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=sra&id="
    # api_key = "702f4a3b99c88a65efe86d822642e3900208"
    suffix_url = "&api_key="

    url = base_url + id + suffix_url + api_key
    http = urllib3.PoolManager()
    response = http.request('GET', url)

    # with open("../dat/xml/" + accn + ".xml", "w") as file:
    #     file.write(response.data.decode("utf-8"))

    try:
        data = xmltodict.parse(response.data)
    except:
        print("Access status getter: Failed to parse xml from response")

    try:
        summary = data['eSummaryResult']['DocSum']['Item'][0]['#text'].lower()
        is_controlled = "controlled" if "controlled" in summary else "public"
    except:
        print("Un/controlled access status couldn't be determined")
        is_controlled = ""

    try:
        info = data['eSummaryResult']['DocSum']['Item'][1]['#text']
    except:
        print("Access status couldn't be determined")

    try:
        search_str = "cluster_name=\""
        start_cn = info.find(search_str)
        cn = info[start_cn + len(search_str):]
        end_info = cn.find("\"")
        cluster_info = cn[:end_info]
    except:
        cluster_info = ""

    return is_controlled, cluster_info


def check_access_status(classified_runs, all_class_names, ncbi_api_key):
    all_projects = []
    project_access = {}
    for keyword_class in classified_runs:
        for run in keyword_class:
            run_accession = run[7]
            project_accession = run[58]
            if not project_accession in all_projects:
                all_projects.append(project_accession)

                # get access status of ncbi
                run_id = get_id_from_accn(run_accession, ncbi_api_key)
                is_controlled, cluster_info = get_access_info(run_id, run_accession, ncbi_api_key)

                project_access[project_accession] = is_controlled

    all_class_names_new = []
    classified_runs_new = []

    for runs_of_class, class_name in zip(classified_runs, all_class_names):
        all_class_names_new.append(class_name + "_public")
        all_class_names_new.append(class_name + "_controlled_access")
        public_runs = []
        controlled_access_runs = []
        for run in runs_of_class:
            project_accession = run[58]
            if project_access[project_accession] == "controlled":
                controlled_access_runs.append(run)
            elif project_access[project_accession] == "public":
                public_runs.append(run)
            else:
                pass  # access status could not be determined...
        classified_runs_new.append(public_runs)
        classified_runs_new.append(controlled_access_runs)

    return classified_runs_new, all_class_names_new


if __name__ == "__main__":
    sys.exit(main())
