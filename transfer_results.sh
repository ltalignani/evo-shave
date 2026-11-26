#!/bin/bash
###################configuration slurm##############################
#SBATCH -A invalbo
#SBATCH --job-name=transfer_results
#SBATCH --time=0-24:00:00
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
#   files_summary.txt, snakemake_report.html, and any graph/stats files
#   in the root directory.
#
# What is kept in the pipeline after cleanup:
#   config/, workflow/, resources/, profile/, raw/, .snakemake/,
#   run_shave.sh, transfer_results.sh, README.md, CHANGELOG.md,
#   Cluster_logs/ (empty), parse_stats_data.py, biblio/
#
# RESUME: safe to re-run after a failure (srun/sbatch killed, node lost).
#   rsync --checksum is per-file incremental. On a re-run the script
#   first compares source vs destination (checksum) and only sends what
#   is missing or changed. The destination is REUSED when it exists
#   without a .transfer_complete marker (= interrupted transfer). A
#   completed archive (marker present) is never reopened: that re-run
#   gets a fresh, timestamped destination instead.

set -euo pipefail

workdir=$(pwd)

###### Read configuration ######
# A bare sbatch shell has no modules loaded: the default python3 (miniconda
# base) lacks PyYAML. Try it first, then fall back to the cluster snakemake
# conda env, which has it.
PY=""
for cand in python3 \
    /shared/software/miniconda_deployment/envs/snakemake-9.4.0/bin/python3; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import yaml" 2>/dev/null; then
        PY="$cand"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "ERROR: no python3 with PyYAML found (needed to read config/config.yaml)." >&2
    exit 1
fi
echo "Config parser: ${PY}"
echo ""

results_dir=$("$PY" -c "
import yaml
c = yaml.safe_load(open('config/config.yaml'))
print(c['transfer']['results_dir'])
")

run_name=$("$PY" -c "
import yaml
c = yaml.safe_load(open('config/config.yaml'))
print(c['transfer']['run_name'])
")

date_stamp=$(date +"%Y-%m-%d")
base_destination="${results_dir}/${run_name}_${date_stamp}"

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
    snakemake_report.html \
    dag.pdf dag.png \
    filegraph.pdf filegraph.png \
    rulegraph.pdf rulegraph.png \
    samtools_qualimap_summary.csv \
    samtools_qualimap_summary.numbers; do
    [ -e "${workdir}/${optional}" ] && transfer_targets+=("$optional")
done

# Targets that actually exist in the source
existing_targets=()
for target in "${transfer_targets[@]}"; do
    [ -e "${workdir}/${target}" ] && existing_targets+=("$target")
done

if [ ${#existing_targets[@]} -eq 0 ]; then
    echo "No transfer targets found in ${workdir} — nothing to do."
    echo "The pipeline may already have been cleaned (transfer already done)."
    exit 0
fi

###### Select destination (resume-aware) ######
# Interrupted transfer = existing destination without .transfer_complete
# marker while source data still exists: resume into the same directory.
# Completed archive = marker present: never reopen it, start a fresh,
# timestamped destination so archives stay separate.
destination="$base_destination"
resumed=false
if [ -d "$destination" ]; then
    if [ -f "${destination}/.transfer_complete" ]; then
        echo "Destination already holds a COMPLETED archive:"
        echo "  ${destination}"
        echo "Starting a fresh, timestamped destination for this (re-)run:"
        destination="${destination}_$(date +%H%M%S)"
    else
        echo "Destination exists, no completion marker, and the pipeline"
        echo "still holds data to transfer."
        echo "RESUMING the interrupted transfer into the same directory:"
        echo "  ${destination}"
        resumed=true
    fi
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

###### Step 1 — Plan: what is left to transfer ######
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 1 — TRANSFER PLAN ##########"
echo -e "------------------------------------------------------------------------"
echo ""

if [ "$resumed" = false ]; then
    # Fresh destination: everything present in the source is pending.
    # No checksum pass needed (there is nothing to compare against).
    pending_targets=("${existing_targets[@]}")
    for target in "${pending_targets[@]}"; do
        echo "  ${target}: will transfer"
    done
else
    # Resume: ask rsync per target what would change. -i itemizes per
    # file; lines starting with '>f' are files that would be sent
    # (missing in destination or checksum-different). Empty result =
    # already in sync.
    pending_targets=()
    for target in "${existing_targets[@]}"; do
        src="${workdir}/${target}"
        plan_out=$(rsync -ai --checksum --dry-run \
            "$src" "${destination}/" 2>&1) || true
        pending_files=$(printf '%s\n' "$plan_out" | grep -c '^>f' || true)
        if [ "$pending_files" -gt 0 ]; then
            pending_targets+=("$target")
            echo "  ${target}: ${pending_files} file(s) to transfer"
        else
            echo "  ${target}: up-to-date (skip)"
        fi
    done
fi

echo ""

###### Step 2 — Transfer the remainder ######
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 2 — TRANSFER ##########"
echo -e "------------------------------------------------------------------------"
echo ""

if [ ${#pending_targets[@]} -eq 0 ]; then
    echo "All targets already in sync — nothing to transfer."
else
    transfer_count=0
    for target in "${pending_targets[@]}"; do
        src="${workdir}/${target}"
        echo "Transferring: $target"
        rsync -a --checksum --info=progress2 \
            "$src" "${destination}/" 2>&1
        transfer_count=$((transfer_count + 1))
    done
    echo ""
    echo "Transfer complete: ${transfer_count} target(s) sent."
fi

###### Step 3 — Verify checksums ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 3 — VERIFICATION ##########"
echo -e "------------------------------------------------------------------------"
echo ""

transfer_ok=true
for target in "${existing_targets[@]}"; do
    src="${workdir}/${target}"
    # -i lists any file that would change; without it rsync is silent
    # and the check could never detect a mismatch. rsync exits non-zero
    # on mismatch — || true keeps set -e from killing the script before
    # the error below is reported.
    diff_output=$(rsync -ai --checksum --dry-run \
        "$src" "${destination}/" 2>&1) || true
    if [ -n "$diff_output" ]; then
        echo "ERROR: Checksum mismatch for: $target"
        echo "$diff_output"
        transfer_ok=false
    fi
done

if [ "$transfer_ok" = false ]; then
    echo ""
    echo "ERROR: Verification failed — source data preserved intact."
    echo "Check the destination manually: ${destination}"
    exit 1
fi

echo "All checksums verified OK."

# Mark the archive as complete (used on re-runs to decide resume vs fresh)
{
    echo "complete"
    echo "timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if [ -n "${SLURM_JOB_ID:-}" ]; then
        echo "slurm_jobid: ${SLURM_JOB_ID}"
    fi
} >"${destination}/.transfer_complete"

###### Step 4 — Clean pipeline ######
echo ""
echo -e "------------------------------------------------------------------------"
echo -e "########## STEP 4 — CLEANUP ##########"
echo -e "------------------------------------------------------------------------"
echo ""

for target in "${existing_targets[@]}"; do
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
echo -e "  3. sbatch run_shave.sh"
echo ""
