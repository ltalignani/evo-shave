rule trimmomatic:
    message:
        "Trimming for {wildcards.sample} sample of the unit {wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=6000,
        runtime=300,
    input:
        r1="raw/{sample}_{unit}_R1.fastq.gz",
        r2="raw/{sample}_{unit}_R2.fastq.gz",
    output:
        r1="trimmed/{sample}_{unit}_trimmomatic_R1.fastq.gz",
        r2="trimmed/{sample}_{unit}_trimmomatic_R2.fastq.gz",
        # reads where trimming entirely removed the mate
        r1_unpaired="trimmed/{sample}_{unit}_trimmomatic_unpaired_R1.fastq.gz",
        r2_unpaired="trimmed/{sample}_{unit}_trimmomatic_unpaired_R2.fastq.gz",
    log:
        "logs/trimmomatic/{sample}_{unit}.log",
    params:
        # list of trimmers (see manual)
        trimmer=[
            "ILLUMINACLIP:resources/adapters/TruSeq2-PE.fa:2:30:15 LEADING:20 TRAILING:3 SLIDINGWINDOW:5:20 AVGQUAL:20 MINLEN:50"
        ],
        # optional parameters
        extra="",
        compression_level="-9",
    # optional specification of memory usage of the JVM that snakemake will respect with global
    # resource restrictions (https://snakemake.readthedocs.io/en/latest/snakefiles/rules.html#resources)
    # and which can be used to request RAM during cluster job submission as `{resources.mem_mb}`:
    # https://snakemake.readthedocs.io/en/latest/executing/cluster.html#job-properties
    wrapper:
        "v4.5.0/bio/trimmomatic/pe"
