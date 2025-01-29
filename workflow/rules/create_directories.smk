rule create_directories:
    output:
        touch("logs/.directories_created"),
    log:
        "logs/OK",
    priority: 10
    shell:
        """
        mkdir -p trimmed/ mapped/ dedup/ calls/ fixed/ graphs/ Cluster_logs/
        mkdir -p logs/awk logs/bwa_mem logs/bgzip logs/gatk3/indelrealigner logs/gatk3/realignertargetcreator logs/gatk3/unifiedgenotyper logs/gatk4/genomicsdbimport logs/gatk4/haplotypecaller logs/fastqc logs/fastq-screen logs/samtools_index logs/samtools_stats logs/setnm logs/trimmomatic logs/md logs/qualimap/bamqc logs/validatesam logs/vcf_stats
        mkdir -p qc/fastqc qc/fastq-screen qc/markdup qc/qualimap_ug qc/qualimap_hc qc/multiqc_data qc/samtools qc/validatesam qc/vcf_stats
        touch logs/.directories_created
        """
