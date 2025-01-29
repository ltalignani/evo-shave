def get_mem_mb(wildcards, attempt):
    return attempt * 16000


reference_file = config["refs"]["reference"]
reference_fai = config["refs"]["index"]
reference_dict = config["refs"]["dict"]


rule indelrealigner:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        bam=rules.SetNmMdAndUqTags.output.bam,
        bai=rules.SetNmMdAndUqTags_index.output,
        ref=reference_file,
        fai=reference_fai,
        dict=reference_dict,
        known="",
        known_idx="",
        target_intervals="dedup/{sample}_{unit}.intervals",
    output:
        bam="dedup/{sample}_{unit}.realigned.bam",
        bai="dedup/{sample}_{unit}.realigned.bai",
    log:
        "logs/gatk3/indelrealigner/{sample}_{unit}.log",
    params:
        extra="--defaultBaseQualities 20 --filter_reads_with_N_cigar",  # optional
    threads: 16
    wrapper:
        "v4.5.0/bio/gatk3/indelrealigner"
