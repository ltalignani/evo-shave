import pandas as pd

# from snakemake.utils import validate
from snakemake.utils import min_version

min_version("8.9.0")


report: "../report/workflow.rst"


###### Config file and sample sheets #####
configfile: "config/config.yaml"


samples = pd.read_table(config["samples"]).set_index("sample", drop=False)
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


##### Wildcard constraints #####
wildcard_constraints:
    vartype="snvs|indels",
    sample="|".join(samples.index),  # output: 'A|B|C|D|E'
    unit="|".join(units.index.get_level_values("unit").unique()),  # output: 'L1|L2'


##### Helper functions #####


# contigs in reference genome
def get_contigs():
    with checkpoints.genome_faidx.get().output[0].open() as fai:
        return pd.read_table(fai, header=None, usecols=[0], squeeze=True, dtype=str)


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
    return r"-R '@RG\tID:{sample}\tSM:{sample}\tPL:{platform}'".format(
        sample=wildcards.sample,
        platform=units.loc[(wildcards.sample, wildcards.unit), "platform"],
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


# Fonction pour déterminer si un échantillon a plusieurs BAMs
def get_bam_list(wildcards):
    units_sample = units.loc[wildcards.sample]["unit"] # return a list of units: [L1, L8]
    if isinstance(units_sample, str): 
        # Si un seul BAM, retourne une liste contenant le fichier BAM unique
        return [f"mapped/{wildcards.sample}_{units_sample}_sorted.bam"]
    else:
        # Retourne une liste de fichiers BAM à fusionner si plusieurs unités
        return [f"mapped/{wildcards.sample}_{unit}_sorted.bam" for unit in units_sample]


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
