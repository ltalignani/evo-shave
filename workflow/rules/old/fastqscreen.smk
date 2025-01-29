configfile: "config/config.yaml"


# PARAMETERS #
CONFIG = config["fastq-screen"]["config"]  # Fastq-screen --conf
MAPPER = config["fastq-screen"]["aligner"]  # Fastq-screen --aligner
SUBSET = config["fastq-screen"]["subset"]  # Fastq-screen --subset


rule fastqscreen:
    message:
        "Fastq-Screen reads contamination checking"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=16000,
        runtime=240,
    params:
        config=CONFIG,
        mapper=MAPPER,
        subset=SUBSET,
        out=directory("qc/fastq-screen"),
    input:
        fastq="raw/{sample}_{unit}_{read}.fastq.gz",
        log="logs/.directories_created",
    output:
        "qc/fastq-screen/{sample}_{unit}_{read}.fastq_screen.png",
        "qc/fastq-screen/{sample}_{unit}_{read}.fastq_screen.txt",
    log:
        "logs/fastq-screen/{sample}_{unit}_{read}_fastq-screen.log",
    envmodules:
        ["fastq-screen/0.15.3", "bwa/0.7.17"],
    shell:
        """
        fastq_screen --threads {resources.cpus_per_task} --conf {params.config} --aligner {params.mapper} --subset {params.subset} --outdir {params.out} {input.fastq} || exit 0
        """

