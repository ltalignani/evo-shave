rule sortsam:
    message:
        "Picard SortSam convert sam into bam"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=16000,
        runtime=240,
    input:
        rules.bwa_mapping.output.sam,
    output:
        temp("results/02_Mapping/{sample}_{unit}_sorted.bam"),
    log:
        "results/11_Reports/sortsam/{sample}_{unit}_bwa_sorted.log",
    params:
        other_options="-SO coordinate --CREATE_INDEX TRUE --MAX_RECORDS_IN_RAM 500000 --TMP_DIR /shared/projects/invalbo/shave-slurm/tmp",
    envmodules:
        ["picard/2.23.5"],
    shell:
        """
        picard SortSam -Xmx{resources.mem_mb}M -I {input} -O {output} {params.other_options} 2> {log}
       """
