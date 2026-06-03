#!/bin/bash
###################configuration slurm##############################
#SBATCH -A invalbo
#SBATCH --job-name=evoshave
#SBATCH --time=5-23:00:00
#SBATCH -p long
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task 1
#SBATCH --mem=4G
#SBATCH -o Cluster_logs/%x-%j-%N.out
#SBATCH -e Cluster_logs/%x-%j-%N.err
#SBATCH --mail-user=loic.talignani@ird.fr
#SBATCH --mail-type=FAIL
###################################################################

# USAGE: sbatch Start_shave.sh

# Purge caches
#echo "purging caches"
#rm -rf /shared/home/ltalignani/.cache/
#rm -rf .snakemake/
#echo "Done."

# Defining cache destination
export XDG_CACHE_HOME=/shared/projects/invalbo/ev-shave/

###Charge module
echo ""

echo -e "Load Modules:"
echo ""

module purge
module load snakemake/8.27.1
module load conda

# set umask to avoid locking each other out of directories
umask 002

###### About ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "##### ABOUT #####"
echo -e "-----------------"
echo ""
echo -e "Name __________________ Start_shave.sh"
echo -e "Author ________________ Loïc Talignani"
echo -e "Affiliation ___________ UMR_MIVEGEC"
echo -e "Aim ___________________ Bash script for SHort-read Alignment pipeline for VEctor v.3"
echo -e "Date __________________ 2025.01.27"
echo -e "Run ___________________ sbatch Start_shave.sh"
echo -e "Latest Modification ___ Added merge_bam rule"

# Set working directory
workdir=$(pwd)            #$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)
max_threads="30"

echo -e "Workdir is "${workdir}

###### Rename samples ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "############## RENAME FASTQ FILES ##############"
echo -e "------------------------------------------------------------------------"
echo ""

# Dossier contenant les fichiers FastQ à renommer
input_directory="raw"

# Parcours des fichiers .fq.gz et .fastq.gz dans le répertoire
for file in "$input_directory"/*.fq.gz "$input_directory"/*.fastq.gz; do
    [ -e "$file" ] || continue

    filename=$(basename "$file")

    # Skip si déjà au bon format {sample}_L{n}_R{1|2}.fastq.gz
    if [[ "$filename" =~ ^.+_L[0-9]+_R[12]\.fastq\.gz$ ]]; then
        echo "Déjà correct : $filename"
        continue
    fi

    # Retirer l'extension pour obtenir la base
    base="${filename%.fq.gz}"
    base="${base%.fastq.gz}"

    # Extraire le read_part (dernier champ après le dernier _)
    read_part="${base##*_}"

    # Normaliser en R1 ou R2 (accepte 1, 2, R1, R2)
    case "$read_part" in
        1|R1) fastq_read="R1" ;;
        2|R2) fastq_read="R2" ;;
        *)
            echo "WARN: Impossible de déterminer le numéro de read pour $filename — fichier ignoré"
            continue
            ;;
    esac

    # Retirer le read_part pour obtenir prefix_lane
    prefix_lane="${base%_${read_part}}"

    # Chercher un identifiant de lane (_L suivi de chiffres, ancré sur _ pour éviter faux positifs)
    lane=$(echo "$prefix_lane" | grep -oE '_L[0-9]+' | tail -1 | sed 's/^_//')

    if [ -n "$lane" ]; then
        prefix="${prefix_lane%_${lane}}"
    else
        lane="L1"
        prefix="$prefix_lane"
    fi

    # Construire le nouveau nom
    new_filename="${prefix}_${lane}_${fastq_read}.fastq.gz"

    # Vérifier si la cible existe déjà
    if [ -f "$input_directory/$new_filename" ]; then
        counter=1
        while [ -f "$input_directory/${prefix}_${lane}_${fastq_read}_dup${counter}.fastq.gz" ]; do
            ((counter++))
        done
        dup_filename="${prefix}_${lane}_${fastq_read}_dup${counter}.fastq.gz"
        echo "WARN: $new_filename existe déjà — renommage de $filename en $dup_filename"
        mv "$file" "$input_directory/$dup_filename"
    else
        mv "$file" "$input_directory/$new_filename"
        echo "Renommé : $filename -> $new_filename"
    fi
done

echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########### CREATE DIRECTORIES ###########"
echo -e "------------------------------------------------------------------------"
echo ""

mkdir -p trimmed/ mapped/ dedup/ calls/ fixed/ graphs/ Cluster_logs/ tmp/ \
logs/{awk,bwa_mem,bgzip,gatk3/{indelrealigner,realignertargetcreator,unifiedgenotyper},gatk4/{genomicsdbimport,haplotypecaller},fastqc,fastq-screen,picard,samtools_{index,stats},setnm,trimmomatic,md,qualimap/bamqc,validatesam,vcf_stats} \
qc/{fastqc,fastq-screen,markdup,qualimap_ug,qualimap_hc,multiqc_data,samtools,validatesam,vcf_stats}

touch logs/.directories_created


###### Call snakemake pipeline ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########### SNAKEMAKE PIPELINE START ###########"
echo -e "------------------------------------------------------------------------"
echo ""

# Suppress pkg_resources deprecation warning (setuptools >= 81 / snakemake 8.9.0)
export PYTHONWARNINGS="ignore::UserWarning:pkg_resources"

echo -e "Unlocking working directory:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --unlock 2>&1

echo ""
echo -e "List conda envs:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --list-conda-envs 2>&1

echo ""
echo -e "Conda environments update:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --conda-cleanup-envs 2>&1

echo ""
echo -e "Conda environments setup:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend mamba --conda-create-envs-only 2>&1

echo ""
echo -e "Dry Run:"
echo ""

snakemake --executor slurm --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend mamba --prioritize create_directories --dry-run 2>&1

echo ""
echo -e "Let's Run!"
echo ""

snakemake --executor slurm --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend mamba --prioritize create_directories --retries 5 --local-cores 8 2>&1

###### Create usefull graphs, summary and logs ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########### SNAKEMAKE PIPELINE LOGS ############"
echo -e "------------------------------------------------------------------------"
echo ""

module load graphviz/2.40.1

mkdir -p ${workdir}/graphs/ 2> /dev/null

graph_list="dag rulegraph filegraph"
extention_list="pdf png"

for graph in ${graph_list} ; do
    for extention in ${extention_list} ; do
	snakemake --workflow-profile profile --keep-going --rerun-incomplete --directory ${workdir}/ --${graph} 2>/dev/null | dot -T${extention} > ${workdir}/graphs/${graph}.${extention} ;
    done
done

snakemake --workflow-profile profile --keep-going --rerun-incomplete --directory ${workdir} --summary > ${workdir}/files_summary.txt 2>&1

###### End managment ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "################## SCRIPT END ###################"
echo -e "------------------------------------------------------------------------"
echo ""

find ${workdir}/logs/ -type f -empty -delete            # Remove empty file (like empty log)
find ${workdir}/ -type d -empty -delete                 # Remove empty directory

time_stamp_end=$(date +"%Y-%m-%d %H:%M")                        # Get date / hour ending analyzes
elapsed_time=${SECONDS}                                         # Get SECONDS counter
minutes=$((${elapsed_time}/60))                                 # / 60 = minutes
seconds=$((${elapsed_time}%60))                                 # % 60 = seconds

echo -e "End Time ______________ ${time_stamp_end}"                                       # Print analyzes ending time
echo -e "Processing Time _______ ${minutes} minutes and ${seconds} seconds elapsed"       # Print total time elapsed

echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########### NEXT STEP — ARCHIVE RESULTS ###########"
echo -e "------------------------------------------------------------------------"
echo ""
echo -e "To transfer results to the archive and reset the pipeline for reuse:"
echo ""
echo -e "  sbatch transfer_results.sh"
echo ""
echo -e "This will: rsync all outputs → verify checksums → clean pipeline."
echo -e "Edit transfer.results_dir and transfer.run_name in config/config.yaml"
echo -e "before running."
echo ""
echo -e "------------------------------------------------------------------------"
echo ""
