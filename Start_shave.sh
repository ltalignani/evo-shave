#!/bin/bash
###################configuration slurm##############################
#SBATCH -A invalbo
#SBATCH --job-name=evoshave
#SBATCH --time=2-23:00:00
#SBATCH -p long
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task 1
#SBATCH --mem=8G
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
module load snakemake/8.9.0
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

# Parcours des fichiers .fq.gz dans le répertoire
for file in "$input_directory"/*.fq.gz; do
    # Extraction des différentes parties du nom du fichier
    filename=$(basename "$file")
    prefix=$(echo "$filename" | cut -d'_' -f1)  # Première partie avant le premier underscore
    lane=$(echo "$filename" | grep -oP 'L\d+')  # Le numéro de lane L suivi d'un chiffre
    fastq_num=$(echo "$filename" | grep -oP '_\d+' | tr -d '_')  # Le numéro de fastq après le second underscore (1 ou 2)
    
    # Conversion du numéro de fastq (1 -> R1, 2 -> R2)
    if [ "$fastq_num" == "1" ]; then
        fastq_read="R1"
    elif [ "$fastq_num" == "2" ]; then
        fastq_read="R2"
    fi
    
    # Construction du nouveau nom de fichier
    new_filename="${prefix}_${lane}_${fastq_read}.fastq.gz"
    
    # Renommage du fichier
    mv "$file" "$input_directory/$new_filename"
    
    echo "Renommé : $filename -> $new_filename"
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

echo -e "Unlocking working directory:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --unlock

echo ""
echo -e "List conda envs:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --list-conda-envs

echo ""
echo -e "Conda environments update:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --conda-cleanup-envs

echo ""
echo -e "Conda environments setup:"
echo ""

snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend conda --conda-create-envs-only  

echo ""
echo -e "Dry Run:"
echo ""


snakemake --executor slurm --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend conda --prioritize create_directories --dry-run

echo ""
echo -e "Let's Run!"
echo ""

snakemake --executor slurm --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores ${max_threads} --use-conda --conda-frontend conda --prioritize create_directories --retries 5 --local-cores 8

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
	snakemake --workflow-profile profile --keep-going --rerun-incomplete --directory ${workdir}/ --${graph} | dot -T${extention} > ${workdir}/graphs/${graph}.${extention} ;
    done
done

snakemake --workflow-profile profile --keep-going --rerun-incomplete --directory ${workdir} --summary > ${workdir}/files_summary.txt

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
echo ""
