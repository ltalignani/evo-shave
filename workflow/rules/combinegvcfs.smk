# PARAMETERS
reference_file = config["refs"]["reference"]


# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000


rule combine_gvcfs:
    message:
        "GATK's CombineGVCFs"
    resources:
        partition="fast",
        cpus_per_task=10,
        mem_mb=get_mem_mb,
        runtime=360,
    input:
        gvcfs=expand(
            "calls/{sample}.{chrom}.g.vcf.gz",
            sample=samples.index,
            chrom=config["chromosomes"],
        ),
        ref=reference_file,
    output:
        gvcf="calls/all.{chrom}.g.vcf.gz",
    log:
        "logs/gatk/combinegvcfs.{chrom}.log",
    params:
        extra=lambda wildcards: f"-L {wildcards.chrom}" if wildcards.chrom else "",
        java_opts="-XX:ParallelGCThreads=10",  # optional
    wrapper:
        "v5.5.2/bio/gatk/combinegvcfs"
