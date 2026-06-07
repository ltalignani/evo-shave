MultiQC — Aggregated Quality Control Report
============================================

MultiQC_ aggregates quality metrics from FastQC (raw read quality), Picard
MarkDuplicates (duplication rates), samtools stats (alignment statistics),
Qualimap (coverage uniformity), and bcftools stats (variant call summary)
into a single interactive HTML report.

Each sample is shown as a separate row. Metrics flagged in yellow or red
indicate samples that may require attention before interpreting downstream
variant calls.

.. _MultiQC: https://multiqc.info/
