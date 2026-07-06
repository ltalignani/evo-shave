sample_unit_pairs = list(units.index)
samples_list = samples.index.tolist()

_mqc_fastqc = [
    f"qc/fastqc/{s}_{u}_R{read}.html"
    for s, u in sample_unit_pairs
    for read in [1, 2]
]
_mqc_markdup = expand("qc/markdup/{sample}_sorted_md_metrics.txt", sample=samples_list)

rule multiqc:
    input:
        _mqc_fastqc,
        _mqc_markdup,
        expand("qc/samtools/{sample}_md.txt", sample=samples_list),
        expand("qc/qualimap_hc/{sample}_report/qualimapReport.html", sample=samples_list),
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
