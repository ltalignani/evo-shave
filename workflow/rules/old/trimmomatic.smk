rule trimmomatic:
    message:
        "Trimming reads"
    resources:
        partition="long",
        cpus_per_task=8,
        mem_mb=6000,
        runtime=300,
    input:
        unpack(get_fastq),
        log="results/11_Reports/.directories_created",
    output:
        r1="results/01_Trimming/{sample}_{unit}_trimmomatic_R1.fastq.gz",
        r2="results/01_Trimming/{sample}_{unit}_trimmomatic_R2.fastq.gz",
        r1_unpaired="results/01_Trimming/{sample}_{unit}_trimmomatic_unpaired_R1.fastq.gz",
        r2_unpaired="results/01_Trimming/{sample}_{unit}_trimmomatic_unpaired_R2.fastq.gz",
        trimlog="results/01_Trimming/{sample}_{unit}.trimlog.txt",
    log:
        "results/11_Reports/trimmomatic/{sample}_{unit}.log",
    params:
        settings=config["trimmomatic"]["settings"],
        phred=config["trimmomatic"]["phred"],
    envmodules:
        ["trimmomatic/0.39"],
    shell:
        """
        trimmomatic PE -threads {resources.cpus_per_task} {params.phred} {input.r1} {input.r2} {output.r1} {output.r1_unpaired} {output.r2} {output.r2_unpaired} {params.settings}
        """
