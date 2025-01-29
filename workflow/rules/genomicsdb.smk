# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000


rule genomics_db_import:
    message:
        "GATK's GenomicsDBImport for multiple g.vcfs for chromosome {wildcards.chrom}"
    resources:
        partition = "long",
        cpus_per_task = 6,
        mem_mb = get_mem_mb,
        runtime = 10080,
    input:
        gvcfs=expand(
            "calls/{sample}.{chrom}.g.vcf.gz",
            sample=samples.index,
            chrom=config["chromosomes"],
        ),
    output:
        db=directory("calls/db.{chrom}"),
    log:
        "logs/gatk4/genomicsdbimport.{chrom}.log",
    params:
        intervals=lambda wildcards: wildcards.chrom,
        db_action="create",                                                 # optional: create | update
        extra=lambda wildcards: f"--tmp-dir {config['resources']['tmpdir']}",  # optional
        java_opts=lambda wildcards, resources: f"-Xmx{resources.mem_mb}M",  # optional
    threads: 2
    wrapper:
        "v4.6.0/bio/gatk/genomicsdbimport"
