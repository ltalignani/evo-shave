def get_mem_mb(wildcards, attempt):
    return attempt * 4000


reference_file = config["refs"]["reference"]


rule validatesam_HC:
    message:
        "picard ValidateSamFile for {wildcards.sample} sample before HaplotypeCaller"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        bam="dedup/{sample}_sorted_md.bam",
        ref=reference_file,
    output:
        "qc/validatesam/{sample}_md.txt",
    params:
        extra="-M SUMMARY",
    conda:
        "../envs/picard-3.2.yaml"
    log:
        "logs/validatesam/{sample}_md_stats.log",
    shell:
        """
        picard ValidateSamFile -Xmx{resources.mem_mb}M -I {input.bam} -R {input.ref} -O {output} {params.extra} 2> {log} || true
        """
