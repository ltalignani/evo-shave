def get_mem_mb(wildcards, attempt):
    return attempt * 8000


# Concatenate per-chromosome VCFs into genome-wide VCF
# (Previously part of bcftools_stats.smk, now separated to preserve merged VCF output capability)

if vcf_output_mode != "per_contig" or skip_filtering:

    if skip_filtering:
        if config["caller"] == "HaplotypeCaller":
            _concat_input = expand("calls/all.{chrom}.vcf.gz", chrom=chromosomes)
        else:
            _concat_input = expand("calls/variants.{chrom}.vcf.gz", chrom=chromosomes)
    else:
        _concat_input = expand("calls/all.{chrom}.filtered.vcf.gz", chrom=chromosomes)
    _concat_output = (
        "calls/all.raw.vcf.gz" if skip_filtering else "calls/all.filtered.vcf.gz"
    )

    rule concat_vcf:
        message:
            "bcftools concat — merging per-chrom VCFs into genome-wide VCF"
        resources:
            partition="fast",
            cpus_per_task=4,
            mem_mb=get_mem_mb,
            runtime=120,
        input:
            _concat_input,
        output:
            _concat_output,
        log:
            "logs/vcf_stats/concat_vcf.log",
        conda:
            "../envs/bcftools-minimal.yaml"
        shell:
            """
            bcftools concat --threads {resources.cpus_per_task} -a -D \
                -O z -o {output} \
                {input} \
                2> {log}
            bcftools index --tbi {output} 2>> {log}
            """
