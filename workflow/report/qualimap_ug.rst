Qualimap — Alignment Coverage Report: {{ snakemake.wildcards.sample }}
=======================================================================

Qualimap_ BAM QC report for sample **{{ snakemake.wildcards.sample }}**,
computed on the indel-realigned BAM (``fixed/{{ snakemake.wildcards.sample }}.fixed.sorted.bam``).

Key metrics to examine: mean coverage, coverage uniformity, GC content bias,
and the proportion of bases covered at 1×, 5×, 10×, and 15×. Low coverage
uniformity or strong GC bias may indicate library preparation issues and
affect variant calling sensitivity.

.. _Qualimap: http://qualimap.conesalab.org/
