# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return max(32000, attempt * 16000)  # Minimum de 32 Go


rule genomics_db_import:
    message:
        "GATK's GenomicsDBImport for multiple g.vcfs for chromosome {wildcards.chrom}"
    resources:
        partition="long",
        mem_mb=get_mem_mb,
        java_mem_overhead_mb=12000,
        runtime=10080,
        tmpdir=config["resources"]["tmpdir"],
    input:
        gvcfs=lambda wildcards: expand(
            "calls/{sample}.{chrom}.g.vcf.gz",
            sample=samples.index,
            chrom=[wildcards.chrom],
        ),
    output:
        db=directory("calls/db.{chrom}"),
    log:
        "logs/gatk4/genomicsdbimport/genomicsdbimport.{chrom}.log",
    params:
        intervals=lambda wildcards: wildcards.chrom,
        db_action="create",
        extra="",
        java_opts="-XX:ParallelGCThreads=10",
    threads: 1
    wrapper:
        "v4.6.0/bio/gatk/genomicsdbimport"
