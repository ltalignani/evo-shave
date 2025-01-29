def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule vcf_stats:
    message:
        "VCF stats for chromosome {wildcards.chrom}"
    resources:
        partition = "fast",
        cpus_per_task = 1,
        mem_mb = get_mem_mb,
        runtime = 240,
    input:
        vcf_file = rules.bgzip.output
    output:
        freq = "qc/vcf_stats/vcf_{chrom}.frq",
        depth = "qc/vcf_stats/vcf_{chrom}.idepth",
        depth_mean = "qc/vcf_stats/vcf_{chrom}.ldepth.mean",
        qual = "qc/vcf_stats/vcf_{chrom}.lqual",
        missing_ind = "qc/vcf_stats/vcf_{chrom}.imiss",
        miss = "qc/vcf_stats/vcf_{chrom}.lmiss",
    conda:
        "../envs/vcftools.yaml"
    log:
        "logs/vcf_stats/vcftools_vcf_{chrom}.log",
    shell:
        """
        vcftools --gzvcf {input} --remove-indels --freq2 --max-alleles 2 --stdout 1> {output.freq}
        vcftools --gzvcf {input} --remove-indels --depth --stdout 1> {output.depth}
        vcftools --gzvcf {input} --remove-indels --site-mean-depth --stdout 1> {output.depth_mean}
        vcftools --gzvcf {input} --remove-indels --site-quality --stdout 1> {output.qual}
        vcftools --gzvcf {input} --remove-indels --missing-indv --stdout 1> {output.missing_ind}
        vcftools --gzvcf {input} --remove-indels --missing-site --stdout 1> {output.miss}
        """
