def get_mem_mb(wildcards, attempt):
    return attempt * 16000


rule bwa_mem:
    message:
        "Mapping with BWA MEM for {wildcards.sample} sample of the unit {wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=16,
        mem_mb=get_mem_mb,
        runtime=360,
    input:
        reads=[
            "trimmed/{sample}_{unit}_trimmomatic_R1.fastq.gz",
            "trimmed/{sample}_{unit}_trimmomatic_R2.fastq.gz",
        ],
        idx=multiext(
            "resources/genomes/AalbF5_filtered.fasta",
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
        extra=r"-T 0 -M -R '@RG\tID:{sample}\tSM:{sample}\tCN:SC\tPL:ILLUMINA'",
        sorting="picard",  # Can be 'none', 'samtools' or 'picard'.
        sort_order="coordinate",  # Can be 'queryname' or 'coordinate'.
        sort_extra="--CREATE_INDEX TRUE",  # Extra args for samtools/picard.
    threads: 16
    wrapper:
        "v4.5.0/bio/bwa/mem"


#(bwa mem -t 16 -R '@RG\tID:Sample_3\tSM:Sample_3\tCN:SC\tPL:ILLUMINA' resources/genomes/AalbF5_filtered.fasta trimmed/Sample_3_1_trimmomatic_R1.fastq.gz trimmed/Sample_3_1_trimmomatic_R2.fastq.gz | picard SortSam  -Xmx9600M -Djava.io.tmpdir=/tmp --CREATE_INDEX TRUE --INPUT /dev/stdin --TMP_DIR /tmp/tmp5n3hgd9g --SORT_ORDER coordinate --OUTPUT mapped/Sample_3_1_sorted.bam)  2> logs/bwa_mem/Sample_3_1_sorted.log
