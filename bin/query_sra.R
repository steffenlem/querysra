#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("argparse"))
library(SRAdb)
library(stringr)

docstring<- "DESCRIPTION \\n\\
SRAmeta database Search \\n\\n\\
DEFAULT FIELDS to search for KEYWORDS:\\n\\
design_description\\n\\
experiment_title\\n\\
study_title,study_abstract\\n\\
study_description\\n\\
sample_attribute\\n\\
"
 
# create parser object
parser <- ArgumentParser(description= docstring, formatter_class= 'argparse.RawTextHelpFormatter')

# Command line options
parser$add_argument("-k", "--keywords", nargs=1, 
    help="Broad keywords to search the SRA database separated by a comma character (\',\') [Required]")
parser$add_argument("-f", "--fields",  nargs='+', default=c("design_description","experiment_title","study_title,study_abstract","study_description","sample_attribute"),
                    help="database fields to search for the provided keywords" )
parser$add_argument("-t", "--taxon_id", default=9606, help="Taxon identifier" )
parser$add_argument("-l", "--library_strategy", default="RNA-Seq", help="Taxon identifier to search samples for" )
parser$add_argument("-db", "--database", help="[OPTIONAL] path to SRAmetadb.sqlite file, otherwise the file will be downloaded (~60 GB)")

# get command line options, if help option encountered print help and exit,
# otherwise if options not found on command line then set defaults,
args <- parser$parse_args()

# check if command line options were provided
if (length(args$keywords) == 0 ) {
    stop(print("keywords not provided"))
}

keywords <- scan(args$keywords, what="", sep="\n")

complete_keyword_str <- ""
for (i in 1:length(keywords)) {

  keyword <- keywords[i]
     keyword_str <- "sra.experiment_title LIKE '%primary%' OR sra.sample_name LIKE '%primary%' OR sra.sample_attribute LIKE '%primary%'"
     complete_keyword_str <- paste(complete_keyword_str, str_replace_all(keyword_str, "primary", keyword))

  if(i != length(keywords)){
    complete_keyword_str <- paste(complete_keyword_str, "OR")
  }
}
complete_keyword_str <- paste(paste('(',complete_keyword_str ), ')')

# read in database
# file.path(system.file('extdata', package='SRAdb'), 'SRAmetadb_demo.sqlite')

if( args$database ==  "NO_FILE") {
    sqlfile <- getSRAdbFile()
} else {
    sqlfile <- file.path(args$database)  # "real" database (~60GB)
}

sra_con <- dbConnect(SQLite(),sqlfile)

# create query
query_string <- paste(sprintf("select * from sra as sra  WHERE sra.library_strategy= %s AND sra.taxon_id= %s AND", sprintf("\"%s\"", args$library_strategy), toString(args$taxon_id)), complete_keyword_str)
query_string
print("-1test")
# search db
human_rna_seq <- dbGetQuery(sra_con, query_string)
print("test")
nrow(human_rna_seq)

write.table(human_rna_seq, file='prefiltering.tsv', sep="\t", col.names=NA)