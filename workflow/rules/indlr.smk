def get_mem_mb(wildcards, attempt):
    return attempt * 16000


reference_file = config["refs"]["reference"]
reference_fai = config["refs"]["index"]
reference_dict = config["refs"]["dict"]


rule indelrealigner:
    message:
        "Indel realignment for {wildcards.sample} sample of the unit {wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        bam=rules.SetNmMdAndUqTags.output.bam,
        bai=rules.SetNmMdAndUqTags_index.output,
        ref=reference_file,
        fai=reference_fai,
        dict=reference_dict,
        target_intervals=rules.realignertargetcreator.output.intervals,
    output:
        bam="dedup/{sample}.realigned.bam",
        bai="dedup/{sample}.realigned.bai",
    log:
        "logs/gatk3/indelrealigner/{sample}.log",
    params:
        extra="--defaultBaseQualities 20 --filter_reads_with_N_cigar",
    conda:
        "../envs/gatk3.yaml"
    container:
        "https://depot.galaxyproject.org/singularity/gatk%3A3.8--hdfd78af_12"
    envmodules:
        ["gatk/3.8"],
    shell:
        """
        gatk3 -T IndelRealigner -I {input.bam} -R {input.ref} --targetIntervals {input.target_intervals} {params.extra} --out {output.bam} 2>&1 {log}
        """
