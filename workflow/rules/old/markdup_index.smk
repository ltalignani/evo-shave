rule samtools_index_markdup:
    message:
        "samtools indexing marked as duplicate BAM file"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=4000,
        runtime=120,
    input:
        markdup=rules.mark_duplicates.output.bam,
    output:
        index="results/02_Mapping/{sample}_{unit}_sorted-mark-dup.bai",
    envmodules:
        ["samtools/1.15.1"],
    log:
        "results/11_Reports/samtools/{sample}_{unit}_sorted-mark-dup-index.log",
    shell:
        """
        samtools index -@ {resources.cpus_per_task} -b {input.markdup} {output.index} &> {log}
        """
