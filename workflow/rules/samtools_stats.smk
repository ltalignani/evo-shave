def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule samtools_stats_HC:
    message:
        "Samtools stats for {wildcards.sample} sample before HaplotypeCaller"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=8000,
        runtime=120,
    input:
        bam="dedup/{sample}_sorted_md.bam",
    output:
        "qc/samtools/{sample}_md.txt",
    params:
        extra=lambda wildcards: f"-r {config['refs']['reference']}",  # Optional: extra arguments.
        region="",  # Optional: region string.
    log:
        "logs/samtools_stats/{sample}_tagged_stats.log",
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        samtools stats -@ {resources.cpus_per_task} {params.extra} {input.bam} 1> {output} 2> {log}
        """
