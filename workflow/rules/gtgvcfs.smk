# PARAMETERS
reference_file = config["refs"]["reference"]


# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000  # Augmente la mémoire allouée à chaque tentative


rule genotype_gvcfs:
    message:
        "GATK's GenotypeGVCFs"
    resources:
        partition="long",
        cpus_per_task=10,
        mem_mb=get_mem_mb,
        runtime=10080,
    input:
        genomicsdb=directory(lambda wildcards: f"calls/db.{wildcards.chrom}"),
        ref=reference_file,
        intervals=lambda wildcards: wildcards.chrom,  # Utilisation correcte des intervalles
    output:
        vcf="calls/all.{chrom}.vcf.gz",
    log:
        "logs/gatk4/genotypegvcfs.{chrom}.log",
    params:
        extra="--include-non-variant-sites",
        java_opts="-XX:ParallelGCThreads=10",
    wrapper:
        "v4.6.0/bio/gatk/genotypegvcfs"
