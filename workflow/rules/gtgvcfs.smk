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
        cpus_per_task = 4,
        mem_mb=get_mem_mb,
        runtime=10080,
    input:
        gvcf=expand(
            "calls/db.{chrom}",
            chrom=config["chromosomes"],
            ),
        ref=reference_file,
    output:
        vcf="calls/all.vcf",
    log:
        "logs/gatk4/genotypegvcfs.log"
    params:
        extra="--tmp-dir {config['resources']['tmpdir']} {config['gatk']['genotypegvcfs']}",  # optional
        java_opts="", # optional
    wrapper:
        "v4.6.0/bio/gatk/genotypegvcfs"
