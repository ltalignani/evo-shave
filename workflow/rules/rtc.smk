def get_mem_mb(wildcards, attempt):
    return attempt * 8000


reference_file = config["refs"]["reference"]
reference_fai = config["refs"]["index"]
reference_dict = config["refs"]["dict"]


rule realignertargetcreator:
    message:
        "RealignerTargetCreator creates a target intervals file for for {wildcards.sample} sample"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=240,
    input:
        bam="dedup/{sample}_tagged.bam",  #rules.SetNmMdAndUqTags.output.bam,
        bai="dedup/{sample}_tagged.bai",  #rules.SetNmMdAndUqTags_index.output,
        ref=reference_file,
        fai=reference_fai,
        dict=reference_dict,
    output:
        intervals="dedup/{sample}.intervals",
    log:
        "logs/gatk3/realignertargetcreator/{sample}.log",
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
        gatk3 -T RealignerTargetCreator --num_threads {resources.cpus_per_task} -R {input.ref} -I {input.bam} {params.extra} --out {output.intervals} 2>&1 {log}
        """
