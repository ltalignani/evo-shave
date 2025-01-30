reference_file = config["refs"]["reference"]


rule SetNmMdAndUqTags:
    message:
        "Picard SetNmMdAndUqTags for {wildcards.sample}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=4000,
        runtime=240,
    input:
        bam=rules.markduplicates_bam.output.bam,
        ref=reference_file,
    output:
        bam="dedup/{sample}_tagged.bam",
    log:
        "logs/setnm/{sample}_tagged.log",
    conda:
        "../envs/picard-3.2.yaml"
    container:
        "https://depot.galaxyproject.org/singularity/picard%3A2.23.5--0"
    shell:
        """
        picard SetNmMdAndUqTags -R {input.ref} -I {input.bam} -O {output.bam} > {log} 2>&1
        """
