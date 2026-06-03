# PARAMETERS
reference_file = config["refs"]["reference"]


# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return max(32000, attempt * 16000)  # Minimum de 32 Go


rule genotype_gvcfs:
    message:
        "GATK's GenotypeGVCFs"
    resources:
        partition="long",
        cpus_per_task=10,
        mem_mb=get_mem_mb,
        runtime=2880,
        tmpdir=config["resources"]["tmpdir"],
    input:
        db_done="calls/db.{chrom}/.done",
        ref=reference_file,
    output:
        "calls/all.{chrom}.vcf.gz",
    log:
        "logs/gatk4/genotypegvcfs.{chrom}.log",
    params:
        extra="--include-non-variant-sites",
        java_opts="-XX:ParallelGCThreads=10",
        db_dir=lambda wildcards: f"calls/db.{wildcards.chrom}",
        intervals=lambda wildcards: wildcards.chrom,
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
gatk --java-options \"-Xmx{{resources.mem_mb}}m\" GenotypeGVCFs \
            -R {input.ref} \
            -V gendb://{params.db_dir} \
            -L {params.intervals} \
            {params.extra} \
            --tmp-dir {resources.tmpdir} \
            -O {output} \
            &> {log}
        """

