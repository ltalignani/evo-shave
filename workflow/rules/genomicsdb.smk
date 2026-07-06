rule genomics_db_import:
    message:
        "GATK's GenomicsDBImport for multiple g.vcfs for chromosome {wildcards.chrom}"
    resources:
        partition="long",
        cpus_per_task=1,
        mem_mb=lambda wildcards, attempt: max(32000, attempt * 16000),
        java_mem_overhead_mb=4000,
        runtime=10080,
        tmpdir=config["resources"]["tmpdir"],
    input:
        gvcfs=lambda wildcards: (
            expand(
                "calls/{sample}.{chrom}.g.vcf.gz",
                sample=samples.index,
                chrom=[wildcards.chrom],
            )
            if hc_scatter
            else expand("calls/{sample}.g.vcf.gz", sample=samples.index)
        ),
    output:
        db=directory("calls/db.{chrom}"),
        done=touch("calls/db.{chrom}/.done"),
    log:
        "logs/gatk4/genomicsdbimport/genomicsdbimport.{chrom}.log",
    params:
        intervals=lambda wildcards: wildcards.chrom,
        extra="--batch-size 50",
        java_opts="-XX:ParallelGCThreads=10",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        # Remove workspace unconditionally: Snakemake pre-creates directory() outputs
        # with a .snakemake_timestamp file, which makes GATK's TileDB fail.
        rm -rf {output.db}

        gatk --java-options \
            "{params.java_opts} \
             -Xmx$(( {resources.mem_mb} - {resources.java_mem_overhead_mb} ))M \
             -Djava.io.tmpdir={resources.tmpdir}" \
            GenomicsDBImport \
            $(printf ' --variant %s' {input.gvcfs}) \
            --genomicsdb-workspace-path {output.db} \
            --intervals {params.intervals} \
            --tmp-dir {resources.tmpdir} \
            --reader-threads 4 \
            {params.extra} \
            > {log} 2>&1
        """
