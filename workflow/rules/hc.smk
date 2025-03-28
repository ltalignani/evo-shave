# PARAMETERS
reference_file = config["refs"]["reference"]
dictionary = config["refs"]["dict"]
index = config["refs"]["index"]

# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000

rule HaplotypeCaller:
    message:
        "GATK's HaplotypeCaller SNPs and indels calling for {wildcards.sample} on {wildcards.chrom}"
    resources:
        partition="long",
        cpus_per_task=4,
        mem_mb=get_mem_mb,
        runtime=180,
    input:
        bam="dedup/{sample}_sorted_md.bam",
        index="dedup/{sample}_sorted_md.bai",
        reference=reference_file,
        dictionary=dictionary,
        fai=index,
    params:
        other_options=config["gatk"]["haplotypecaller"],  # -ERC GVCF
        output_mode=config["gatk"]["output_mode"],  # EMIT_ALL_CONFIDENT_SITES
        interval=lambda wildcards: f"-L {wildcards.chrom}" if wildcards.chrom else "",
    output:
        "calls/{sample}.{chrom}.g.vcf.gz",
    conda:
        "../envs/gatk4.yaml"
    log:
        "logs/gatk4/haplotypecaller/{sample}.{chrom}.log",
    shell:
        """
        gatk HaplotypeCaller --java-options "-Xmx{resources.mem_mb}M" \
        -R {input.reference} \
        -I {input.bam} \
        -O {output[0]} \
        {params.other_options} \
        --output-mode {params.output_mode} \
        {params.interval} &> {log}
        """