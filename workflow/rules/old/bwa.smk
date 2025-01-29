reference_file = config["refs"]["reference"]


rule bwa_mapping:
    message:
        "BWA-MEM mapping sample reads against reference genome sequence"
    resources:
        partition="fast",
        cpus_per_task=16,
        mem_mb=32000,
        runtime=1200,
    input:
        reads=get_trimmed_reads,
    output:
        sam=temp("results/02_Mapping/{sample}_{unit}.sam"),
    params:
        ref=reference_file,
        extra=r"'@RG\tID:{sample}\tSM:{sample}\tCN:SC\tPL:ILLUMINA'",  # Manage ReadGroup
    log:
        "results/11_Reports/bwa/{sample}_{unit}.o",
    envmodules:
        ["bwa/0.7.17"],
    shell:
        """
        bwa mem -M -T 0 -t {resources.cpus_per_task} -R {params.extra} {params.ref} {input.reads} > {output.sam}
        """
