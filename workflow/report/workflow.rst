SHAVE Pipeline Run Report
=========================

**Pipeline:** SHAVE — SHort-read Alignment pipeline for VEctors

**Caller:** HaplotypeCaller

**Reference genome:** {{ snakemake.config["refs"]["reference"] }}

**Samples:** {{ snakemake.config["samples"] }}

**MarkDuplicates:** {{ "skipped (ddRAD-seq mode)" if snakemake.config["markdup"].get("skip", False) else "enabled" }}

**VCF output mode:** {{ snakemake.config["chromosomes"]["vcf_output"] }}

----

This report was generated automatically by SHAVE after pipeline completion.
It includes alignment quality control (Qualimap), a consolidated QC summary
(MultiQC), and per-chromosome variant statistics (vcftools).

Navigate between sections using the tabs above. The **Rules** tab shows the
complete workflow graph and per-rule runtime statistics. The **Statistics** tab
summarises job execution times and resource usage.

.. _GATK: https://gatk.broadinstitute.org/hc/en-us
.. _BWA: http://bio-bwa.sourceforge.net/
.. _MultiQC: https://multiqc.info/
.. _Samtools: http://www.htslib.org/
.. _FastQC: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
.. _Qualimap: http://qualimap.conesalab.org/
