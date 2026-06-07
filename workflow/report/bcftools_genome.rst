bcftools stats — Genome-wide Filtered Variant Statistics
=========================================================

Summary statistics computed by bcftools_ on the genome-wide hard-filtered
VCF (``calls/all.filtered.vcf.gz``), after merging all per-chromosome
filtered callsets.

Key metrics: total number of SNVs and indels passing filters, ts/tv ratio
(expected ~2.0–2.1 for whole-genome data; deviations may indicate filtering
artefacts or reference bias), indel length distribution, and per-sample
heterozygosity rates.

Hard filtering thresholds applied: see ``config/config.yaml``
(``filtering.hard`` section).

.. _bcftools: https://samtools.github.io/bcftools/
