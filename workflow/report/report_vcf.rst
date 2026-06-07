VCF Statistics Report — {{ snakemake.wildcards.chrom }}
========================================================

Interactive variant statistics report for chromosome/scaffold
**{{ snakemake.wildcards.chrom }}**, generated from the hard-filtered VCF
using VCFtools and rendered with R/plotly.

The report includes: allele frequency spectrum, depth distribution per
variant site, genotype quality distribution, missing data rates per
sample, and per-site missingness. These plots help identify systematic
biases (e.g. strand bias, low-complexity regions) and samples with
unexpectedly high missing data rates that may need to be excluded from
downstream population genomic analyses.
