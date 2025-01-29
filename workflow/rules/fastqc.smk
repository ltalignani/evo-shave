rule fastqc:
    message:
        "Quality Control with FastQC for {wildcards.sample} sample of the unit {wildcards.unit}, read {wildcards.read}"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=16000,
        runtime=240,
    threads: 8
    input:
        lambda wildcards: get_fastq(wildcards)[f"r{wildcards.read}"],  # Sélection du fichier correspondant à read=1 ou 2
    output:
        html="qc/fastqc/{sample}_{unit}_R{read}.html",  
        zip="qc/fastqc/{sample}_{unit}_R{read}_fastqc.zip",  # le suffixe _fastqc.zip est nécessaire pour multiqc
    params:
        extra="--quiet",
    log:
        "logs/fastqc/{sample}_{unit}_R{read}.log",
    wrapper:
        "v4.4.0/bio/fastqc"