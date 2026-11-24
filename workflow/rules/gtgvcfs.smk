# PARAMETERS
reference_file = config["refs"]["reference"]


# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return max(32000, attempt * 16000)  # Minimum de 32 Go


# ── 1. Exporter le GVCF combiné depuis le GenomicsDB ────────────────────────────
# GenotypeGVCFs litant gendb:// directement souffre d'une fuite mémoire du
# GenomicsDB 1.3+ (broadinstitute/gatk#8989, confirmé par les mainteneurs GATK) :
# la mémoire RSS grimpe sans borne au fil des contigus (~2 GB/Mb, heap Java stable)
# et le job est OOM-killed quel que soit le -Xmx. Contournement officiel : extraire
# d'abord le GVCF combiné avec SelectVariants (mémoire bornée), puis alimenter
# GenotypeGVCFs avec ce fichier.

rule export_gendb_gvcf:
    message:
        "GATK's SelectVariants — export du GVCF combiné pour {wildcards.chrom}"
    resources:
        partition="long",
        cpus_per_task=2,
        mem_mb=get_mem_mb,
        runtime=2160,
        tmpdir=config["resources"]["tmpdir"],
    input:
        db_done="calls/db.{chrom}/.done",
        ref=reference_file,
    output:
        temp("calls/all.{chrom}.gendb.g.vcf.gz"),
    log:
        "logs/gatk4/export_gendb_gvcf.{chrom}.log",
    params:
        java_opts="-XX:ParallelGCThreads=2",
        db_dir=lambda wildcards: f"calls/db.{wildcards.chrom}",
        intervals=lambda wildcards: wildcards.chrom,
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk --java-options "{params.java_opts} -Xmx{resources.mem_mb}m \
            -Djava.io.tmpdir={resources.tmpdir}" \
            SelectVariants \
            -R {input.ref} \
            -V gendb://{params.db_dir} \
            -L {params.intervals} \
            -O {output} \
            > {log} 2>&1
        """


# ── 2. Appeler les génotypes à partir du GVCF exporté ───────────────────────────

rule genotype_gvcfs:
    message:
        "GATK's GenotypeGVCFs"
    resources:
        partition="long",
        cpus_per_task=10,
        mem_mb=get_mem_mb,
        runtime=2880,
        tmpdir=config["resources"]["tmpdir"],
    input:
        gvcf="calls/all.{chrom}.gendb.g.vcf.gz",
        ref=reference_file,
    output:
        "calls/all.{chrom}.vcf.gz",
    log:
        "logs/gatk4/genotypegvcfs.{chrom}.log",
    params:
        extra="--include-non-variant-sites",
        java_opts="-XX:ParallelGCThreads=10",
    conda:
        "../envs/gatk4.yaml"
    shell:
        """
        gatk --java-options "{params.java_opts} -Xmx{resources.mem_mb}m \
            -Djava.io.tmpdir={resources.tmpdir}" \
            GenotypeGVCFs \
            -R {input.ref} \
            -V {input.gvcf} \
            {params.extra} \
            --tmp-dir {resources.tmpdir} \
            -O {output} \
            > {log} 2>&1
        """
