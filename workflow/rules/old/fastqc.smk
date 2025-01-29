rule fastqc_quality_control:
    message:
        "FastQC reads quality controling"
    priority: 50
    resources:
        partition="fast",
        cpus_per_task=12,
        mem_mb=8000,
        runtime=120,
    input:
        unpack(get_fastq),
        log="results/11_Reports/.directories_created",
    output:
        "qc/fastqc/{sample}_{unit}_R1_fastqc.html",
        "qc/fastqc/{sample}_{unit}_R2_fastqc.html",
        "qc/fastqc/{sample}_{unit}_R1_fastqc.zip",
        "qc/fastqc/{sample}_{unit}_R2_fastqc.zip",
    params:
        outdir=directory("results/qc/fastqc/"),
    log:
        r1="results/11_Reports/quality/{sample}_{unit}_R1_fastqc.log",
        r2="results/11_Reports/quality/{sample}_{unit}_R2_fastqc.log",
    envmodules:
        ["fastqc/0.11.8"],
    shell:
        """
        fastqc --quiet --threads {resources.cpus_per_task} --outdir {params.outdir} {input.r1} &> {log.r1}
        fastqc --quiet --threads {resources.cpus_per_task} --outdir {params.outdir} {input.r2} &> {log.r2}
        """
