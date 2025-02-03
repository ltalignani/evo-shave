# Définition correcte des paires sample-unit
sample_unit_pairs = list(units.index)  # Liste explicite des tuples (sample, unit)
samples_list = samples.index.tolist()  # Liste explicite des samples


rule multiqc:
    input:
        expand(
            "qc/fastqc/{sample}_{unit}_R{read}.html",
            sample=[s for s, u in sample_unit_pairs],
            unit=[u for s, u in sample_unit_pairs],
            read=[1, 2],
        ),
        expand(
            "qc/markdup/{sample}_sorted_md_metrics.txt",
            sample=samples_list,
        ),
        expand(
            "qc/samtools/{sample}.fixed.sorted.txt",
            sample=samples_list,
        ),
        expand(
            "qc/qualimap_ug/{sample}_report/qualimapReport.html",
            sample=samples_list,
        ),
    output:
        "qc/multiqc.html",
        directory("qc/multiqc_data"),
    params:
        extra="--verbose",
    log:
        "logs/multiqc.log",
    wrapper:
        "v4.6.0/bio/multiqc"


use rule multiqc as multiqc_HC with:
    input:
        expand(
            "qc/fastqc/{sample}_{unit}_R{read}.html",
            sample=[s for s, u in sample_unit_pairs],
            unit=[u for s, u in sample_unit_pairs],
            read=[1, 2],
        ),
        expand(
            "qc/markdup/{sample}_sorted_md_metrics.txt",
            sample=samples_list,
        ),
        expand(
            "qc/samtools/{sample}_md.txt",
            sample=samples_list,
        ),
        expand(
            "qc/qualimap_hc/{sample}_report/qualimapReport.html",
            sample=samples_list,
        ),
    output:
        "qc/multiqc.html",
        directory("qc/multiqc_data"),
