def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule sort_by_queryname:
    message:
        "Sorting BAM by queryname for {wildcards.sample}-{wildcards.unit} using Picard SortSam"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=120,
    input:
        rules.indelrealigner.output.bam,
    output:
        temp("fixed/{sample}.queryname.bam"),
    log:
        "logs/picard/{sample}.queryname_sort.log",
    conda:
        "../envs/picard-3.2.yaml"
    shell:
        """
        picard SortSam -I {input} -O {output} --SORT_ORDER queryname --TMP_DIR tmp/ > {log} 2>&1 || true
        """


rule picard_fixmate:
    message:
        "Fixing mate information in {wildcards.sample}-{wildcards.unit} using Picard"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=120,
    input:
        "fixed/{sample}.queryname.bam",
    output:
        temp("fixed/{sample}.fixed.bam"),
    log:
        "logs/picard/{sample}.fixed.log",
    conda:
        "../envs/picard-3.2.yaml"
    shell:
        """
        picard FixMateInformation -I {input} -O {output} --TMP_DIR tmp/ > {log} 2>&1 || true
        """


rule sort_by_coordinate:
    message:
        "Sorting BAM by coordinate for {wildcards.sample}-{wildcards.unit} using Picard SortSam"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=120,
    input:
        "fixed/{sample}.fixed.bam",
    output:
        "fixed/{sample}.fixed.sorted.bam",
    log:
        "logs/picard/{sample}.coordinate_sort.log",
    conda:
        "../envs/picard-3.2.yaml"
    shell:
        """
        picard SortSam -I {input} -O {output} --SORT_ORDER coordinate --CREATE_INDEX true --TMP_DIR tmp/ > {log} 2>&1 || true
        """