def get_mem_mb(wildcards, attempt):
    if isinstance(attempt, int) and attempt > 0:
        return attempt * 16000
    else:
        raise ValueError("Attempt must be a positive integer")


reference_file = config["refs"]["reference"]


rule bwa_mem:
    message:
        "Mapping with BWA MEM for {wildcards.sample} sample of the unit {wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=16,
        mem_mb=lambda wildcards, attempt: get_mem_mb(wildcards, attempt),
        runtime=360,
    input:
        reads=[
            "trimmed/{sample}_{unit}_trimmomatic_R1.fastq.gz",
            "trimmed/{sample}_{unit}_trimmomatic_R2.fastq.gz",
        ],
        ref=reference_file,
        idx=multiext(
            reference_file,
            ".amb",
            ".ann",
            ".bwt",
            ".pac",
            ".sa",
        ),
    output:
        "mapped/{sample}_{unit}_sorted.bam",
    log:
        "logs/bwa_mem/{sample}_{unit}_sorted.log",
    params:
        extra=lambda wildcards: get_read_group(wildcards),  #r"-R '@RG\tID:{sample}\tSM:{sample}\tCN:SC\tPL:{platform}'",
        msp="-M",  # Mark Shorter Splits for Picard compatibility
        out_al="-T 0",
        sort_order="coordinate",  # Can be 'queryname' or 'coordinate'.
        sort_extra="--CREATE_INDEX TRUE",  # Extra args for samtools/picard.
    threads: 16
    conda:
        "../envs/bwa-0.7.17.yaml"
    shell:
        """
        (bwa mem {params.msp} {params.out_al} -t {resources.cpus_per_task} {params.extra} \
            {input.ref} \
            {input.reads} | picard SortSam -Xmx{resources.mem_mb}M \
            -Djava.io.tmpdir=tmp \
            --INPUT /dev/stdin \
            --TMP_DIR tmp \
            --SORT_ORDER {params.sort_order} {params.sort_extra} \
            --OUTPUT {output}) 2> {log}
        """
