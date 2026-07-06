rule create_directories:
    output:
        touch("logs/.directories_created"),
    log:
        "logs/OK",
    priority: 10
    shell:
        """
        mkdir -p trimmed/ mapped/ dedup/ calls/ fixed/ graphs/ flags/ Cluster_logs/ tmp/
        mkdir -p logs/gatk4/genomicsdbimport logs/gatk4/haplotypecaller logs/gatk4/filter logs/fastqc logs/fastq-screen logs/samtools_index logs/samtools_stats logs/trimmomatic logs/md logs/qualimap/bamqc logs/validatesam logs/vcf_stats
        mkdir -p qc/fastqc qc/fastq-screen qc/markdup qc/qualimap_hc qc/multiqc_data qc/samtools qc/validatesam qc/vcf_stats
        touch logs/.directories_created
        """
