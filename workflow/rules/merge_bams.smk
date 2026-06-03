def get_input(wildcards):
    input_list = list()
    # Vérifiez si le sample est dans la table `units` pour trouver les unités associées
    units_for_sample = units[units["sample"] == wildcards.sample]
    # Pour chaque unité trouvée, ajoutez le chemin du fichier bam à la liste `input`
    for index, row in units_for_sample.iterrows():
        bam_path = "mapped/{}_{}_sorted.bam".format(wildcards.sample, row["unit"])
        input_list.append(bam_path)
    return input_list


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
        runtime=30,
    run:
        # Convertir input en liste pour manipulation
        input_files = list(input)

        if len(input_files) == 1:
            # Si seule un unit existe, copier simplement le fichier
            # L'index sera créé par MarkDuplicates (--CREATE_INDEX TRUE)
            shell(
                """
                cp {input[0]} {output.bam}
                echo "Single unit: BAM file copied from {input[0]}" > {log}
                """
            )
        else:
            # Merger plusieurs units avec Picard
            # Picard créera l'index automatiquement (--CREATE_INDEX true)
            bams = " --INPUT ".join(input_files)
            shell(
                f"""
                module load picard/2.23.5
                picard MergeSamFiles --INPUT {bams} --OUTPUT {{output.bam}} --USE_THREADING true --SORT_ORDER coordinate {{params.extra}} --TMP_DIR {{params.tmpdir}} > {{log}} 2>&1"""
            )
