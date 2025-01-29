rule mark_duplicates:
    message:
        "Picard MarkDuplicates remove PCR duplicates"
    resources:
        partition="long",
        cpus_per_task=1,
        mem_mb=128000,
        runtime=2400,
    benchmark:
        "benchmarks/{sample}_{unit}_markduplicates.tsv"
    input:
        rules.bwa_mem.output,
    output:
        bam="results/02_Mapping/{sample}_{unit}_sorted-mark-dup.bam",
        metrics="qc/markdup/{sample}_{unit}_sorted-mark-dup_metrics.txt",
    log:
        "results/11_Reports/markduplicates/{sample}_{unit}_sorted-mark-dup.log",
    params:
        other_options="--CREATE_INDEX TRUE --VALIDATION_STRINGENCY SILENT",
    envmodules:
        ["picard/2.23.5"],
    shell:
        """
        picard MarkDuplicates -Xmx{resources.mem_mb}M {params.other_options} -I {input} -O {output.bam} -M {output.metrics}
        """
