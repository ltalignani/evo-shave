import re

import pandas as pd

# from snakemake.utils import validate
from snakemake.utils import min_version

min_version("9.0.0")


report: "../report/workflow.rst"


###### Config file and sample sheets #####
configfile: "config/config.yaml"


samples = pd.read_table(config["samples"], dtype=str).set_index("sample", drop=False)
# validate(samples, schema="../schemas/samples.schema.yaml")

units = pd.read_table(config["units"], dtype=str).set_index(
    ["sample", "unit"], drop=False
)
units.index = units.index.set_levels(
    [i.astype(str) for i in units.index.levels]
)  # enforce str in index
# validate(units, schema="../schemas/units.schema.yaml")

units = units.sort_index()
# Increase performance - avoid warnings: "indexing past lexsort depth may impact performance"


##### Contig list resolution #####


def get_chromosomes(config):
    """Build contig list at parse time from config.
    Supports backwards-compatible plain list, manual list under chromosomes.list,
    or auto-detection from the reference .fai with optional size and name filters.
    """
    chrom_cfg = config.get("chromosomes", {})

    # Backwards compat: chromosomes was previously a plain YAML list
    if isinstance(chrom_cfg, list):
        return chrom_cfg

    if not chrom_cfg.get("auto", False):
        contigs = chrom_cfg.get("list", [])
        if not contigs:
            raise ValueError(
                "chromosomes.auto is false but chromosomes.list is empty. "
                "Add contig names under chromosomes.list or set auto: true."
            )
        return contigs

    # Auto-detect from .fai
    fai_path = config["refs"]["index"]
    fai = pd.read_table(
        fai_path,
        header=None,
        names=["name", "length", "offset", "linebases", "linewidth"],
        usecols=[0, 1],
    )
    fai.columns = ["name", "length"]
    contigs = fai["name"].tolist()
    lengths = dict(zip(fai["name"], fai["length"]))

    min_size = chrom_cfg.get("min_size", 0)
    if min_size:
        contigs = [c for c in contigs if lengths[c] >= min_size]

    pattern = chrom_cfg.get("pattern", "")
    if pattern:
        contigs = [c for c in contigs if re.match(pattern, c)]

    if not contigs:
        raise ValueError(
            f"No contigs remain after filtering (fai: {fai_path}). "
            f"Check chromosomes.min_size ({min_size}) and chromosomes.pattern ('{pattern}')."
        )

    return contigs


chromosomes = get_chromosomes(config)

vcf_output_mode = (
    config["chromosomes"].get("vcf_output", "both")
    if isinstance(config["chromosomes"], dict)
    else "both"
)

skip_filtering = config.get("filtering", {}).get("skip", False)


def get_final_vcf(wildcards):
    """Return the final per-chromosome VCF for downstream QC rules.

    When filtering.skip is True (e.g. ddRAD-seq), points directly to the raw
    caller output. When False, points to the hard-filtered merged VCF.
    """
    if skip_filtering:
        if config["caller"] == "HaplotypeCaller":
            return f"calls/all.{wildcards.chrom}.vcf.gz"
        else:
            return f"calls/variants.{wildcards.chrom}.vcf.gz"
    return f"calls/all.{wildcards.chrom}.filtered.vcf.gz"


##### Wildcard constraints #####
wildcard_constraints:
    vartype="snvs|indels",
    sample="|".join(samples.index),
    unit="|".join(units.index.get_level_values("unit").unique()),
    chrom="|".join(chromosomes),


def get_fastq(wildcards):
    """Get fastq files of given sample-unit."""
    fastqs = units.loc[(wildcards.sample, wildcards.unit), ["fq1", "fq2"]].dropna()
    if len(fastqs) == 2:
        return {"r1": fastqs.fq1, "r2": fastqs.fq2}  # voici ce qui est retourné
    return {"r1": fastqs.fq1}


def is_single_end(sample, unit):
    """Return True if sample-unit is single end."""
    return pd.isnull(units.loc[(sample, unit), "fq2"])


def get_read_group(wildcards):
    """Denote sample name and platform in read group."""
    return (
        r"-R '@RG\tID:{sample}_{unit}\tSM:{sample}\tLB:{sample}\tPL:{platform}'".format(
            sample=wildcards.sample,
            unit=wildcards.unit,
            platform=units.loc[(wildcards.sample, wildcards.unit), "platform"],
        )
    )


def get_trimmed_reads(wildcards):
    """Get trimmed reads of given sample-unit."""
    if not is_single_end(**wildcards):
        # paired-end sample
        return expand(
            "trimmed/{sample}_{unit}_trimmomatic_R{group}.fastq.gz",
            group=[1, 2],
            **wildcards,
        )
    # single end sample
    return "trimmed/{sample}_{unit}_trimmomatic.fastq.gz".format(**wildcards)


def get_sample_bams(wildcards):
    """Get all aligned reads of given sample."""
    return expand(
        "mapped/{sample}_{unit}_sorted.bam",
        sample=wildcards.sample,
        unit=units.loc[wildcards.sample].unit,
    )

# def get_regions_param(regions=config["processing"].get("restrict-regions"), default=""):
#     if regions:
#         params = "--intervals '{}' ".format(regions)
#         padding = config["processing"].get("region-padding")
#         if padding:
#             params += "--interval-padding {}".format(padding)
#         return params
#     return default
# def get_call_variants_params(wildcards, input):
#     return (
#         get_regions_param(
#             regions=input.regions, default="--intervals {}".format(wildcards.contig)
#         )
#         + config["params"]["gatk"]["HaplotypeCaller"]
#     )
# def get_recal_input(bai=False):
#     # case 1: no duplicate removal
#     f = "results/mapped/{sample}-{unit}.sorted.bam"
#     if config["processing"]["remove-duplicates"]:
#         # case 2: remove duplicates
#         f = "results/dedup/{sample}-{unit}.bam"
#     if bai:
#         if config["processing"].get("restrict-regions"):
#             # case 3: need an index because random access is required
#             f += ".bai"
#             return f
#         else:
#             # case 4: no index needed
#             return []
#     else:
#         return f
# def get_snpeff_reference():
#     return "{}.{}".format(config["ref"]["build"], config["ref"]["snpeff_release"])
# def get_vartype_arg(wildcards):
#     return "--select-type-to-include {}".format(
#         "SNP" if wildcards.vartype == "snvs" else "INDEL"
#     )
# def get_filter(wildcards):
#     return {"snv-hard-filter": config["filtering"]["hard"][wildcards.vartype]}
