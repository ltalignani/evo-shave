def get_input(wildcards):
    input = list()
    # Vérifiez si le sample est dans la table `units` pour trouver les unités associées
    units_for_sample = units[units["sample"] == wildcards.sample]
    # Pour chaque unité trouvée, ajoutez le chemin du fichier bam à la liste `input`
    for index, row in units_for_sample.iterrows():
        input.append("mapped/{}_{}_sorted.bam".format(wildcards.sample, row["unit"]))
    return input

rule merge_bams:
    message:
        "Merging BAM files for {wildcards.sample}"
    input:
        lambda wildcards: get_input(wildcards),
    output:
        bam="merged/{sample}_merged.bam",
    log:
        "logs/merge_bams/{sample}_merged.log",
    params:
        extra="--CREATE_INDEX true",
        tmpdir="tmp",
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=16000,
        runtime=120,
    run:
        if len(input) == 1:
            # Si seule un unit existe, copier simplement le fichier
            shell(
                """
                cp {input[0]} {output.bam}
                touch {log}
                """
            )
        else:
            bams = " --INPUT ".join(input)
            shell(
                """
                module load picard/2.23.5
                picard MergeSamFiles --INPUT {bams} --OUTPUT {output.bam} --USE_THREADING true --SORT_ORDER coordinate {params.extra} --TMP_DIR {params.tmpdir} > {log} 2>&1"""
            )