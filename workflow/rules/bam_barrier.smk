rule all_bams_ready:
    """
    Barrier rule: all per-sample deduplicated BAMs and their indices must exist
    before any variant calling job (HaplotypeCaller / UnifiedGenotyper) is submitted.

    This prevents thousands of variant-calling jobs from flooding the SLURM queue
    while BAM-production jobs are still pending, which would rapidly deplete FairShare.
    """
    input:
        bams=expand("dedup/{sample}_sorted_md.bam", sample=samples.index),
        bais=expand("dedup/{sample}_sorted_md.bai", sample=samples.index),
    output:
        touch("flags/all_bams_ready.flag"),
