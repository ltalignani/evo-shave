rule SetNmMdAndUqTags_index:
    message:
        "Samtools index tagged bams"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=4000,
        runtime=240,
    input:
        rules.SetNmMdAndUqTags.output.bam,
    output:
        bai="results/04_Polishing/{sample}_{unit}_bwa_sorted-mark-dup-tagged.bai",
    log:
        "results/11_Reports/samtools/{sample}_{unit}_bwa_sorted-mark-dup-tagged.bai.log",
    envmodules:
        ["samtools/1.15.1"],
    shell:
        """
        samtools index -@ {resources.cpus_per_task} -b {input} -o {output.bai} &> {log}
        """
