rule fastqc:
    message:
        "FastQC reads quality controling"
    resources:
        partition="fast",
        cpus_per_task=12,
        mem_mb=8000,
        runtime=120,
    input:
        "raw/{sample}_{unit}_{read}.fastq.gz",
    output:
        "qc/fastqc/{sample}_{unit}_{read}_fastqc.html",
        "qc/fastqc/{sample}_{unit}_{read}_fastqc.zip",
    params:
        outdir=directory("results/qc/fastqc/"),
    log:
        "logs/fastqc/{sample}_{unit}_{read}_fastqc.log",
    envmodules:
        ["fastqc/0.11.8"],
    shell:
        """
        fastqc --quiet --threads {resources.cpus_per_task} --outdir {params.outdir} {input} &> {log}
        """
