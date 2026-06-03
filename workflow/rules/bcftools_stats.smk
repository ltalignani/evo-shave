def get_mem_mb(wildcards, attempt):
    return attempt * 8000


# ── 1. Stats on raw VCF (pre-filter, per chromosome) ──────────────────────────

rule bcftools_stats_raw:
    message:
        "bcftools stats — pre-filter VCF for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=2,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf=lambda wildcards: (
            f"calls/all.{wildcards.chrom}.vcf.gz"
            if config["caller"] == "HaplotypeCaller"
            else f"calls/variants.{wildcards.chrom}.vcf.gz"
        ),
    output:
        "qc/vcf_stats/{chrom}.raw.bcftools_stats.txt",
    log:
        "logs/vcf_stats/bcftools_stats_raw.{chrom}.log",
    conda:
        "../envs/bcftools-1.15.1.yaml"
    shell:
        """
        bcftools stats {input.vcf} > {output} 2> {log}
        """


# ── 2. Stats on filtered VCF (post-filter, per chromosome) ────────────────────

rule bcftools_stats_filtered:
    message:
        "bcftools stats — post-filter VCF for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=2,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf="calls/all.{chrom}.filtered.vcf.gz",
    output:
        "qc/vcf_stats/{chrom}.filtered.bcftools_stats.txt",
    log:
        "logs/vcf_stats/bcftools_stats_filtered.{chrom}.log",
    conda:
        "../envs/bcftools-1.15.1.yaml"
    shell:
        """
        bcftools stats {input.vcf} > {output} 2> {log}
        """


# ── 3 & 4. Genome-wide concat + stats (skipped when vcf_output: "per_contig") ──

if vcf_output_mode != "per_contig":

    rule bcftools_concat:
        message:
            "bcftools concat — merging filtered per-chrom VCFs into genome-wide VCF"
        resources:
            partition="fast",
            cpus_per_task=4,
            mem_mb=get_mem_mb,
            runtime=120,
        input:
            expand("calls/all.{chrom}.filtered.vcf.gz", chrom=chromosomes),
        output:
            "calls/all.filtered.vcf.gz",
        log:
            "logs/vcf_stats/bcftools_concat.log",
        conda:
            "../envs/bcftools-1.15.1.yaml"
        shell:
            """
            bcftools concat --threads {resources.cpus_per_task} -a -D \
                -O z -o {output} \
                {input} \
                2> {log}
            bcftools index --tbi {output} 2>> {log}
            """

    rule bcftools_stats_genome:
        message:
            "bcftools stats — genome-wide filtered VCF"
        resources:
            partition="fast",
            cpus_per_task=2,
            mem_mb=get_mem_mb,
            runtime=120,
        input:
            vcf="calls/all.filtered.vcf.gz",
        output:
            "qc/vcf_stats/all.filtered.bcftools_stats.txt",
        log:
            "logs/vcf_stats/bcftools_stats_genome.log",
        conda:
            "../envs/bcftools-1.15.1.yaml"
        shell:
            """
            bcftools stats {input.vcf} > {output} 2> {log}
            """
