sample_unit_pairs = list(units.index)
samples_list = samples.index.tolist()

_mqc_fastqc = [
    f"qc/fastqc/{s}_{u}_R{read}.html"
    for s, u in sample_unit_pairs
    for read in [1, 2]
]
_mqc_markdup = expand("qc/markdup/{sample}_sorted_md_metrics.txt", sample=samples_list)
_mqc_vcf_raw = expand("qc/vcf_stats/{chrom}.raw.bcftools_stats.txt", chrom=chromosomes)

_mqc_bcftools_per_chrom = (
    []
    if skip_filtering
    else expand("qc/vcf_stats/{chrom}.filtered.bcftools_stats.txt", chrom=chromosomes)
)
_mqc_bcftools_genome = (
    ["qc/vcf_stats/all.raw.bcftools_stats.txt"]
    if skip_filtering
    else (
        ["qc/vcf_stats/all.filtered.bcftools_stats.txt"]
        if vcf_output_mode != "per_contig"
        else []
    )
)

if config["caller"] == "UnifiedGenotyper":

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}.fixed.sorted.txt", sample=samples_list),
            expand("qc/qualimap_ug/{sample}_report/qualimapReport.html", sample=samples_list),
            _mqc_vcf_raw,
            *_mqc_bcftools_per_chrom,
            *_mqc_bcftools_genome,
        output:
            report(
                "qc/multiqc.html",
                caption="../report/multiqc.rst",
                category="Quality Control",
            ),
            directory("qc/multiqc_data"),
        params:
            extra="--verbose",
        log:
            "logs/multiqc.log",
        wrapper:
            "v4.6.0/bio/multiqc"

else:  # HaplotypeCaller

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}_md.txt", sample=samples_list),
            expand("qc/qualimap_hc/{sample}_report/qualimapReport.html", sample=samples_list),
            _mqc_vcf_raw,
            *_mqc_bcftools_per_chrom,
            *_mqc_bcftools_genome,
        output:
            report(
                "qc/multiqc.html",
                caption="../report/multiqc.rst",
                category="Quality Control",
            ),
            directory("qc/multiqc_data"),
        params:
            extra="--verbose",
        log:
            "logs/multiqc.log",
        wrapper:
            "v4.6.0/bio/multiqc"
