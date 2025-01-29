def get_mem_mb(wildcards, attempt):
    return attempt * 32000


reference_file = config["refs"]["reference"]


rule create_bam_list:
    message:
        "Generating bam.list file"
    input:
        expand(
            "fixed/{sample}.fixed.sorted.bam",
            sample=samples.index
        ),
    output:
        bam_list=temp("fixed/bam.list"),
    shell:
        """
        find fixed -name '*fixed.sorted.bam' > {output.bam_list}
        """


rule unifiedgenotyper:
    message:
        "UnifiedGenotyper calling SNVs for chromosome {wildcards.chrom}"
    resources:
        partition="long",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=10080,
    input:
        bam=rules.create_bam_list.output.bam_list,
        ref=reference_file,
    output:
        temp("calls/variants.{chrom}.vcf"),
    conda:
        "../envs/gatk3.yaml"
    log:
        "logs/unifiedgenotyper/variants.{chrom}.log",
    shell:
        """
        gatk3 -T UnifiedGenotyper --num_threads {resources.cpus_per_task} --num_cpu_threads_per_data_thread {resources.cpus_per_task} -I {input.bam} -R {input.ref} \
        -L {chrom} --out {output} --genotype_likelihoods_model BOTH \
        --genotyping_mode DISCOVERY --heterozygosity 0.015 --heterozygosity_stdev 0.05 --indel_heterozygosity 0.001 --downsampling_type BY_SAMPLE \
        -dcov 250 --output_mode EMIT_ALL_SITES --min_base_quality_score 17 -stand_call_conf 0.0 -contamination 0.0 -A DepthPerAlleleBySample \
        -A RMSMappingQuality -A Coverage -A FisherStrand -A StrandOddsRatio -A BaseQualityRankSumTest -A MappingQualityRankSumTest -A QualByDepth \
        -A ReadPosRankSumTest -XA ExcessHet -XA InbreedingCoeff -XA MappingQualityZero -XA HaplotypeScore -XA SpanningDeletions -XA ChromosomeCounts \
        &> {log}
        """


rule bgzip:
    message:
        "UnifiedGenotyper calling SNVs for chromosome {wildcards.chrom}"
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=4000,
        runtime=120,
    input:
        rules.unifiedgenotyper.output,
    output:
        "calls/variants.{chrom}.vcf.gz",
    conda:
        "../envs/htslib.yaml"
    log:
        "logs/bgzip/variants.{chrom}.vcf.gz.log",
    shell:
        """
            bgzip -c --threads {resources.cpus_per_task} {input} > {output} 2> {log}
        """
