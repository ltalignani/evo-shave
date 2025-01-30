def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule qualimap:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        # BAM aligned, splicing-aware, to reference genome
        bam=rules.sort_by_coordinate.output,
    output:
        directory("qc/qualimap_ug/{sample}"),
        report_html="qc/qualimap_ug/{sample}/qualimapReport.html",
    conda:
        "../envs/qualimap.yaml"
    log:
        "logs/qualimap/bamqc/{sample}.log",
    shell:
        """
        mkdir -p qc/qualimap_ug/{wildcards.sample}
        qualimap bamqc -bam {input.bam} -c -nt {resources.cpus_per_task} --java-mem-size={resources.mem_mb}M -outdir qc/qualimap_ug/{wildcards.sample} &> {log}
        """


use rule qualimap as qualimap_HC with:
    input:
        bam=rules.markduplicates_bam.output.bam,
    output:
        directory("qc/qualimap_hc/{sample}"),
        report_html="qc/qualimap_hc/{sample}/qualimapReport.html",
