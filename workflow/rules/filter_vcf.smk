reference_file = config["refs"]["reference"]


def get_raw_vcf(wildcards):
    """Return raw (pre-filter) per-chromosome VCF depending on caller."""
    if config["caller"] == "HaplotypeCaller":
        return f"calls/all.{wildcards.chrom}.vcf.gz"
    else:
        return f"calls/variants.{wildcards.chrom}.vcf.gz"


def get_mem_mb(wildcards, attempt):
    return attempt * 8000


# ── 1. Extract SNVs ────────────────────────────────────────────────────────────

rule select_snvs:
    message:
        "GATK SelectVariants — extracting SNVs for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf=get_raw_vcf,
        ref=reference_file,
    output:
        "calls/snvs.{chrom}.vcf.gz",
    log:
        "logs/gatk4/filter/select_snvs.{chrom}.log",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk SelectVariants \
            -R {input.ref} \
            -V {input.vcf} \
            --select-type-to-include SNP \
            -O {output} \
            &> {log}
        """


# ── 2. Extract indels ──────────────────────────────────────────────────────────

rule select_indels:
    message:
        "GATK SelectVariants — extracting indels for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf=get_raw_vcf,
        ref=reference_file,
    output:
        "calls/indels.{chrom}.vcf.gz",
    log:
        "logs/gatk4/filter/select_indels.{chrom}.log",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk SelectVariants \
            -R {input.ref} \
            -V {input.vcf} \
            --select-type-to-include INDEL \
            -O {output} \
            &> {log}
        """


# ── 3. Hard-filter SNVs ────────────────────────────────────────────────────────

rule filter_snvs:
    message:
        "GATK VariantFiltration — hard-filtering SNVs for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf="calls/snvs.{chrom}.vcf.gz",
        ref=reference_file,
    output:
        "calls/snvs.{chrom}.filtered.vcf.gz",
    log:
        "logs/gatk4/filter/filter_snvs.{chrom}.log",
    params:
        filters=config["filtering"]["hard"]["snvs"],
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk VariantFiltration \
            -R {input.ref} \
            -V {input.vcf} \
            --filter-expression "{params.filters}" \
            --filter-name "hard_snv_filter" \
            -O {output} \
            &> {log}
        """


# ── 4. Hard-filter indels ──────────────────────────────────────────────────────

rule filter_indels:
    message:
        "GATK VariantFiltration — hard-filtering indels for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf="calls/indels.{chrom}.vcf.gz",
        ref=reference_file,
    output:
        "calls/indels.{chrom}.filtered.vcf.gz",
    log:
        "logs/gatk4/filter/filter_indels.{chrom}.log",
    params:
        filters=config["filtering"]["hard"]["indels"],
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk VariantFiltration \
            -R {input.ref} \
            -V {input.vcf} \
            --filter-expression "{params.filters}" \
            --filter-name "hard_indel_filter" \
            -O {output} \
            &> {log}
        """


# ── 5. Keep PASS SNVs ──────────────────────────────────────────────────────────

rule select_pass_snvs:
    message:
        "GATK SelectVariants — keeping PASS SNVs for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf="calls/snvs.{chrom}.filtered.vcf.gz",
        ref=reference_file,
    output:
        "calls/snvs.{chrom}.pass.vcf.gz",
    log:
        "logs/gatk4/filter/select_pass_snvs.{chrom}.log",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk SelectVariants \
            -R {input.ref} \
            -V {input.vcf} \
            --exclude-filtered \
            -O {output} \
            &> {log}
        """


# ── 6. Keep PASS indels ────────────────────────────────────────────────────────

rule select_pass_indels:
    message:
        "GATK SelectVariants — keeping PASS indels for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        vcf="calls/indels.{chrom}.filtered.vcf.gz",
        ref=reference_file,
    output:
        "calls/indels.{chrom}.pass.vcf.gz",
    log:
        "logs/gatk4/filter/select_pass_indels.{chrom}.log",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk SelectVariants \
            -R {input.ref} \
            -V {input.vcf} \
            --exclude-filtered \
            -O {output} \
            &> {log}
        """


# ── 7. Merge PASS SNVs + indels ────────────────────────────────────────────────

rule merge_filtered_vcf:
    message:
        "Picard MergeVcfs — merging PASS SNVs + indels for {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        snvs="calls/snvs.{chrom}.pass.vcf.gz",
        indels="calls/indels.{chrom}.pass.vcf.gz",
    output:
        temp("calls/all.{chrom}.filtered.vcf.gz")
        if vcf_output_mode == "merged"
        else "calls/all.{chrom}.filtered.vcf.gz",
    log:
        "logs/gatk4/filter/merge_filtered.{chrom}.log",
    conda:
        "../envs/picard-3.2.yaml"
    shell:
        """
        picard MergeVcfs \
            -I {input.snvs} \
            -I {input.indels} \
            -O {output} \
            > {log} 2>&1
        """
