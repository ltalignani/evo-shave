def get_mem_mb(wildcards, attempt):
    return attempt * 8000

rule sort_by_queryname:
    message:
        "Sorting BAM by queryname for {wildcards.sample}-{wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=120,
    input:
        rules.indelrealigner.output.bam,
    output:
        "sorted/{sample}_{unit}.queryname.bam",
    log:
        "logs/samtools/{sample}_{unit}.queryname_sort.log",
    conda:
        "../envs/samtools.yaml",
    shell:
        """
        samtools sort -n -o {output} {input} > {log} 2>&1
        """

rule samtools_fixmate:
    message:
        "Fixing mate information in {wildcards.sample}-{wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=240,
    input:
        "sorted/{sample}_{unit}.queryname.bam",
    output:
        "fixed/{sample}_{unit}.fixed.bam",
    log:
        "logs/samtools/{sample}_{unit}.fixed.log",
    conda:
        "../envs/samtools.yaml",
    shell:
        """
        samtools fixmate -@ {resources.cpus_per_tasks} -rcmM -O bam {input} {output} > {log} 2>&1
        """

rule sort_by_coordinate:
    message:
        "Sorting BAM by coordinate for {wildcards.sample}-{wildcards.unit}"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=120,
    input:
        "fixed/{sample}_{unit}.fixed.bam",
    output:
        "sorted/{sample}_{unit}.fixed.sorted.bam",
    log:
        "logs/samtools/{sample}_{unit}.coordinate_sort.log",
    conda:
        "../envs/samtools.yaml",
    shell:
        """
        samtools sort -o {output} {input} > {log} 2>&1
        """
