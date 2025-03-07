def get_mem_mb(wildcards, attempt):
    mem = attempt * 8000
    print(f"Attempt {attempt}: Allocating {mem} MB of memory")
    return mem


rule markduplicates_bam:
    message:
        "Mark Duplicates for {wildcards.sample} sample"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=lambda wildcards, attempt: get_mem_mb(wildcards, attempt),
        runtime=120,
    input:
        bams="merged/{sample}_merged.bam",
    output:
        bam="dedup/{sample}_sorted_md.bam",
        metrics="qc/markdup/{sample}_sorted_md_metrics.txt",
    log:
        "logs/md/{sample}_sorted_md.log",
    params:
        extra=lambda wildcards: f"--REMOVE_DUPLICATES {str(config['markdup']['remove-duplicates']).upper()} --CREATE_INDEX TRUE --VALIDATION_STRINGENCY SILENT",
    wrapper:
        "v4.5.0/bio/picard/markduplicates"
