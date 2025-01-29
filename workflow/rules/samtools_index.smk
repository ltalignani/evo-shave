rule samtools_index:
    message:
        "Samtools index for {wildcards.sample} sample of the unit {wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=4000,
        runtime=120,
    input:
        rules.markduplicates_bam.output.bam,
    output:
        "dedup/{sample}_sorted_md.bai",
    log:
        "logs/samtools_index/{sample}_sorted_md.log",
    params:
        extra="",  # optional params string
    threads: 4  # This value - 1 will be sent to -@
    wrapper:
        "v4.5.0/bio/samtools/index"


use rule samtools_index as SetNmMdAndUqTags_index with:
    input:
        rules.SetNmMdAndUqTags.output.bam,
    output:
        "dedup/{sample}_tagged.bai",
    log:
        "logs/samtools_index/{sample}_tagged_bai.log",
    params:
        extra="",
