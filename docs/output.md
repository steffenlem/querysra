# steffenlem/querysra: Output

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

<!-- TODO nf-core: Write this documentation describing your workflow's output -->

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/)
and processes data using the following steps:

* [SRAdb](#sradb) - Search the SRA database for samples containing the preselection keywords.
* [keyword_filtering](#keywordfiltering) - Filtering and classification of samples.

## SRAdb

Samples in the SRA database are scanned for a provided set of prefiltering keywords to be contained in the fields sample attribute, sample name, or experiment name. Moreover, additional information to filter for the taxon identifier and the library strategy can be provided. The criterion of samples to be returned is as follows: Only if one of the provided prefiltering keywords is identified and the taxon identifier and library strategy are identical with the selected choice, the sample is included in the output subset.


**Output directory: `results/SRAdb`**

* `prefiltering.tsv`
  * Contains all samples with fitting taxon ID, library strategy and one or more prefiltering keywords

## keyword_filtering

[keyword_filtering] 

**Output directory: `results/keyword_filtering`**

* `download_lists/`
  * Directory containing newline separated lists of SRA run accession for each class
* `sample_overview/`
  * Directory containing tsv files for each class. The tsv files contain information about each samples' attributes and keywords on which the classification was based on.
* `summary_statistic/`
  * Directory containing a summary file for each class. The summary file contains the number of samples, the number of projects and the size of each project.
