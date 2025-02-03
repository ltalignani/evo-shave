# PARAMETERS
reference_file = config["refs"]["reference"]


# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000


rule genotype_gvcfs:
    message:
        "GATK's GenotypeGVCFs"
    resources:
        partition="long",
        mem_mb=get_mem_mb,
        runtime=10080,
        tmpdir=config["resources"]["tmpdir"],
    input:
        gvcf=expand(
            "calls/db.{chrom}",
            chrom=config["chromosomes"],
        ),
        ref=reference_file,
    output:
        vcf="calls/all.{chrom}.vcf.gz",
    log:
        "logs/gatk4/genotypegvcfs.{chrom}.log",
    params:
        extra="",  # optional
        java_opts="-XX:ParallelGCThreads=10",  # optional
    wrapper:
        "v4.6.0/bio/gatk/genotypegvcfs"
