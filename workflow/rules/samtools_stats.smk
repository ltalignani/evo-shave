def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule samtools_stats:
    message:
        "Samtools stats for {wildcards.sample} sample of the unit {wildcards.unit} before UnifiedGenotyper"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=8000,
        runtime=120,
    input:
        bam=rules.sort_by_coordinate.output,
    output:
        "qc/samtools/{sample}.fixed.sorted.txt",
    params:
        extra=lambda wildcards: f"-r {config['refs']['reference']}",  # Optional: extra arguments.
        region="",  # Optional: region string.
    log:
        "logs/samtools_stats/{sample}_fixed_sorted_stats.log",
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        samtools stats -@ {resources.cpus_per_task} {params.extra} {input.bam} 1> {output} 2> {log}
        """


if config["caller"] == "HaplotypeCaller":
    use rule samtools_stats as samtools_stats_HC with:
        message:
            "Samtools stats for {wildcards.sample} sample of the unit {wildcards.unit} before HaplotypeCaller"
        input:
            "dedup/{sample}_sorted_md.bam",
        output:
            "qc/samtools/{sample}_md.txt",
        log:
            "logs/samtools_stats/{sample}_tagged_stats.log",
