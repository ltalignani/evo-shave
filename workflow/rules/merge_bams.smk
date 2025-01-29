rule copy_single_bam:
    message:
        "Copying single BAM file for {wildcards.sample}"
    input:
        bam=lambda wildcards: get_bam_list(wildcards)[0],  # Prend le BAM unique
        bai=lambda wildcards: get_bam_list(wildcards)[0].replace(".bam", ".bai"),
    output:
        bam="merged/{sample}_merged.bam",
        bai="merged/{sample}_merged.bai",
    log:
        "logs/copy_bams/{sample}_copied.log",
    shell:
        """
        cp {input.bam} {output.bam}
        cp {input.bai} {output.bai}
        echo "Copied {input.bam} to {output.bam}" > {log}
        """


rule merge_bams:
    message:
        "Merging BAM files for {wildcards.sample}"
    input:
        bams=lambda wildcards: get_bam_list(wildcards),
    output:
        bam="merged/{sample}_merged.bam",
        bai="merged/{sample}_merged.bai",
    log:
        "logs/merge_bams/{sample}_merged.log",
    params:
        extra="--CREATE_INDEX true",
        tmpdir="tmp",
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=16000,
        runtime=120,
    conda:
        "../envs/picard-3.2.yaml"
    shell:
        """
        picard MergeSamFiles \
            {params.extra} \
            --TMP_DIR {params.tmpdir} \
            --INPUT {input.bams} \
            --OUTPUT {output.bam} \
            --USE_THREADING true \
            --SORT_ORDER coordinate \
            > {log} 2>&1
        """
