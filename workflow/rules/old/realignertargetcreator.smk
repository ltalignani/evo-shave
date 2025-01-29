def get_mem_mb(wildcards, attempt):
    return attempt * 8000


reference_file = config["refs"]["reference"]
reference_fai = config["refs"]["index"]
reference_dict = config["refs"]["dict"]


rule realignertargetcreator:
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=240,
    input:
        bam="dedup/{sample}_{unit}_tagged.bam",  #rules.SetNmMdAndUqTags.output.bam,
        bai="dedup/{sample}_{unit}_tagged.bai",  #rules.SetNmMdAndUqTags_index.output,
        ref=reference_file,
        fai=reference_fai,
        dict=reference_dict,
        known="",
        known_idx="",
    output:
        intervals="dedup/{sample}_{unit}.intervals",
    log:
        "logs/gatk3/realignertargetcreator/{sample}_{unit}.log",
    params:
        extra="--defaultBaseQualities 20 --filter_reads_with_N_cigar",  # optional
    threads: 1
    wrapper:
        "v4.5.0/bio/gatk3/realignertargetcreator"
