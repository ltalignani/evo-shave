#!/bin/bash
###################configuration slurm##############################
#SBATCH -A invalbo
#SBATCH --job-name=transfer_results
#SBATCH --time=0-12:00:00
#SBATCH -p long
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task 4
#SBATCH --mem=4G
#SBATCH -o Cluster_logs/%x-%j-%N.out
#SBATCH -e Cluster_logs/%x-%j-%N.err
#SBATCH --mail-user=loic.talignani@ird.fr
#SBATCH --mail-type=END,FAIL
###################################################################

# USAGE: sbatch transfer_results.sh
#
# Transfers all pipeline results to a dated archive directory, verifies
# the transfer with checksums, then cleans the pipeline for reuse.
#
# What is transferred: calls/, qc/, dedup/, merged/, trimmed/, mapped/,
#   fixed/, logs/, graphs/, Cluster_logs/, README.md, CHANGELOG.md,
#   files_summary.txt, and any graph/stats files in the root directory.
#
# What is kept in the pipeline after cleanup:
#   config/, workflow/, resources/, profile/, raw/, .snakemake/,
#   Start_shave.sh, transfer_results.sh, README.md, CHANGELOG.md,
#   Cluster_logs/ (empty), parse_stats_data.py, biblio/

set -euo pipefail

workdir=$(pwd)

###### Read configuration ######
results_dir=$(python3 -c "
import yaml
c = yaml.safe_load(open('config/config.yaml'))
print(c['transfer']['results_dir'])
")

run_name=$(python3 -c "
import yaml
c = yaml.safe_load(open('config/config.yaml'))
print(c['transfer']['run_name'])
")

date_stamp=$(date +"%Y-%m-%d")
destination="${results_dir}/${run_name}_${date_stamp}"

# Avoid overwriting an existing destination (same-day re-run)
if [ -d "$destination" ]; then
    destination="${destination}_$(date +%H%M%S)"
fi

###### About ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "##### TRANSFER RESULTS #####"
echo -e "----------------------------"
echo ""
echo -e "Source ________________ ${workdir}"
echo -e "Destination ___________ ${destination}"
echo -e "Date __________________ $(date +"%Y-%m-%d %H:%M")"
echo ""

mkdir -p "$destination" 2>&1

###### Build list of targets to transfer ######
transfer_targets=(
    "calls"
    "qc"
    "dedup"
    "merged"
    "trimmed"
    "mapped"
    "fixed"
    "logs"
    "graphs"
    "Cluster_logs"
    "README.md"
    "CHANGELOG.md"
)

# Add optional root-level files if they exist
for optional in files_summary.txt \
                dag.pdf dag.png \
                filegraph.pdf filegraph.png \
                rulegraph.pdf rulegraph.png \
                samtools_qualimap_summary.csv \
                samtools_qualimap_summary.numbers; do
    [ -e "${workdir}/${optional}" ] && transfer_targets+=("$optional")
done

###### Step 1 — Transfer ######
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 1 — TRANSFER ##########"
echo -e "------------------------------------------------------------------------"
echo ""

transfer_count=0
for target in "${transfer_targets[@]}"; do
    src="${workdir}/${target}"
    if [ -e "$src" ]; then
        echo "Transferring: $target"
        rsync -a --checksum --info=progress2 \
            "$src" "${destination}/" 2>&1
        ((transfer_count++))
    else
        echo "Skipped (not found): $target"
    fi
done

echo ""
echo "Transfer complete: ${transfer_count} items sent."

###### Step 2 — Verify checksums ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 2 — VERIFICATION ##########"
echo -e "------------------------------------------------------------------------"
echo ""

transfer_ok=true
for target in "${transfer_targets[@]}"; do
    src="${workdir}/${target}"
    if [ -e "$src" ]; then
        diff_output=$(rsync -a --checksum --dry-run \
            "$src" "${destination}/" 2>&1)
        if [ -n "$diff_output" ]; then
            echo "ERROR: Checksum mismatch for: $target"
            echo "$diff_output"
            transfer_ok=false
        fi
    fi
done

if [ "$transfer_ok" = false ]; then
    echo ""
    echo "ERROR: Verification failed — source data preserved intact."
    echo "Check the destination manually: ${destination}"
    exit 1
fi

echo "All checksums verified OK."

###### Step 3 — Clean pipeline ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 3 — CLEANUP ##########"
echo -e "------------------------------------------------------------------------"
echo ""

for target in "${transfer_targets[@]}"; do
    src="${workdir}/${target}"
    if [ -e "$src" ] && [ "$target" != "README.md" ] && [ "$target" != "CHANGELOG.md" ] && [ "$target" != "Cluster_logs" ]; then
        rm -rf "$src"
        echo "Removed: $target"
    fi
done

# Recreate empty Cluster_logs for next run
mkdir -p "${workdir}/Cluster_logs"
echo "Recreated empty: Cluster_logs/"

###### End ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "################## TRANSFER COMPLETE ###################"
echo -e "------------------------------------------------------------------------"
echo ""
echo -e "Results archived at:"
echo -e "  ${destination}"
echo ""
echo -e "Pipeline ready for next run:"
echo -e "  1. Update config/samples.tsv and config/units.tsv"
echo -e "  2. Place new FASTQs in raw/"
echo -e "  3. sbatch Start_shave.sh"
echo ""
