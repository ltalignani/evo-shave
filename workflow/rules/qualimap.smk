def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule qualimap_ug:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        # BAM aligned, splicing-aware, to reference genome
        bam=rules.sort_by_coordinate.output,
    output:
        directory("qc/qualimap/{sample}_report"),
        report_html="qc/qualimap/{sample}_report/qualimapReport.html",
    conda:
        "../envs/qualimap.yaml"
    log:
        "logs/qualimap_ug/bamqc/{sample}_report.log",
    shell:
        """
        mkdir -p qc/qualimap_ug/{wildcards.sample}_report/
        qualimap bamqc -bam {input.bam} -c -nt {resources.cpus_per_task} --java-mem-size={resources.mem_mb}M -outdir qc/qualimap_ug/{wildcards.sample}_report &> {log}
        """


rule qualimap_hc:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        bam=rules.markduplicates_bam.output.bam,
    output:
        directory("qc/qualimap_hc/{sample}_report"),
        report_html="qc/qualimap_hc/{sample}_report/qualimapReport.html",
    conda:
        "../envs/qualimap.yaml"
    log:
        "logs/qualimap_hc/bamqc/{sample}_report.log",
    shell:
        """
        mkdir -p qc/qualimap_hc/{wildcards.sample}_report/
        qualimap bamqc -bam {input.bam} -c -nt {resources.cpus_per_task} --java-mem-size={resources.mem_mb}M -outdir qc/qualimap_hc/{wildcards.sample}_report &> {log}
        """
