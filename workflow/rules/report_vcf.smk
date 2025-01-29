def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule report_vcf:
    message: 
        "Execute rule report_vcf for chromosome {wildcards.chrom}"
    resources:
        partition = "fast",
        cpus_per_task = 1,
        mem_mb = get_mem_mb,
        runtime = 240,
    input:
        freq = rules.vcf_stats.output.freq,
        depth = rules.vcf_stats.output.depth,
        depth_mean = rules.vcf_stats.output.depth_mean,
        qual = rules.vcf_stats.output.qual,
        missing_ind = rules.vcf_stats.output.missing_ind,
        miss = rules.vcf_stats.output.miss
    output:
        report = "qc/vcf_stats/report_vcf_{chrom}.html",
    conda:
        "../envs/r.yaml"
    log:
        'logs/vcf_stats/report_{chrom}.o',
    script:
        """
        ../scripts/report_vcf.Rmd
        """
