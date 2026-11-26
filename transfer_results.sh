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
# RESUME: safe to re-run after a failure (srun/sbatch killed, node lost),
#   even days later.
#   - Destination: the script scans results_dir for archives named
#     <run_name>_YYYY-MM-DD* and resumes into the NEWEST one without a
#     .transfer_complete marker — even if it was created on an earlier
#     day. A completed archive (marker present) is never reopened:
#     that re-run gets a fresh, timestamped destination instead.
#   - Plan: a quick size+mtime comparison (stat only, no data read)
#     decides what is still missing, so planning takes seconds even
#     for multi-TB targets. An interrupted rsync leaves a missing or
#     partial (smaller) file, both detected here.
#   - Transfer: plain rsync (size+mtime skip rule), no hashing.
#   - Verification: one full --checksum pass over source and
#     destination is the integrity gate that runs BEFORE the pipeline
#     is cleaned. That is the only checksum pass of the whole run.
#     The job's own SLURM log (Cluster_logs/*-<jobid>-*.out/.err) is
#     excluded: it grows while the job runs, so comparing it would be a
#     false mismatch. It is archived by the next run, once stable.

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

# When run via sbatch, this job's own SLURM log (Cluster_logs/<jobname>-<jobid>-<node>.out/.err)
# is written WHILE the script runs. If it were included in the plan,
# the transfer, or the verification, the verification gate would see a
# file whose source copy keeps growing -> false "checksum mismatch" ->
# exit 1 -> and every sbatch re-run creates a NEW growing log (new job
# id) -> livelock. Exclude the current job's own logs from all rsync
# calls; they will be archived by the NEXT run, once stable.
rsync_excludes=()
if [ -n "${SLURM_JOB_ID:-}" ]; then
    rsync_excludes+=(
        --exclude "*-${SLURM_JOB_ID}-*.out"
        --exclude "*-${SLURM_JOB_ID}-*.err"
    )
fi

###### Select destination (resume-aware, works across days) ######
# The archive directory is dated, but an interrupted transfer may be
# days old: "today's" directory alone is not a reliable resume target.
# Rule: scan results_dir for this run_name's dated archives.
#   - NEWEST archive WITHOUT a .transfer_complete marker, dated within
#     the last 7 days -> interrupted transfer: resume into it.
#     (Older incomplete archives are left alone: re-opening one from a
#     previous experiment would mix two runs' data in one archive.)
#   - otherwise -> fresh dated directory for today; if today's is
#     already completed, add a time suffix so archives stay separate.
# Directory names start with <run_name>_YYYY-MM-DD, which sort
# chronologically, so the last match of the glob is the newest.
MAX_RESUME_AGE_DAYS=7
destination="${results_dir}/${run_name}_$(date +%Y-%m-%d)"
resumed=false
for archive in "${results_dir}/${run_name}_"*; do
    [ -d "$archive" ] || continue
    [ -f "${archive}/.transfer_complete" ] && continue
    archive_date=$(basename "$archive" | sed -E 's/^[^_]+_([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
    age_days=$((($(date +%s) - $(date -d "$archive_date" +%s)) / 86400))
    if [ "$age_days" -gt "$MAX_RESUME_AGE_DAYS" ]; then
        echo "WARNING: incomplete archive is ${age_days} days old (> ${MAX_RESUME_AGE_DAYS}):"
        echo "  ${archive}"
        echo "It will NOT be resumed (stale). Delete it manually if it is"
        echo "no longer needed, or start a fresh archive (default)."
        continue
    fi
    destination="$archive"
    resumed=true
done

if [ "$resumed" = true ]; then
    echo "Found an INCOMPLETE archive (no .transfer_complete marker):"
    echo "  ${destination}"
    echo "RESUMING the interrupted transfer into it (date-independent)."
elif [ -d "$destination" ]; then
    # Today's directory exists and holds a COMPLETED archive.
    echo "Today's archive is already COMPLETED:"
    echo "  ${destination}"
    echo "Starting a fresh, timestamped destination for this (re-)run:"
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
    # Resume: quick size+mtime diff per target (stat only — no data is
    # read, so the plan finishes in seconds even for multi-TB targets).
    # An interrupted rsync leaves a missing file or a partial one
    # (smaller size), both detected here. -i itemizes per item; lines
    # starting with '>' are items to send (files, symlinks, ...) and
    # lines starting with 'cd' are directories to create (matters for
    # EMPTY target dirs such as Cluster_logs/ — without them the
    # destination would lack the dir and STEP 3 would report a false
    # mismatch). In-sync items are not listed at all.
    pending_targets=()
    for target in "${existing_targets[@]}"; do
        src="${workdir}/${target}"
        plan_out=$(rsync -ain --dry-run \
            "${rsync_excludes[@]}" \
            "$src" "${destination}/" 2>&1) || true
        pending_items=$(printf '%s\n' "$plan_out" | grep -cE '^(>|cd)' || true)
        if [ "$pending_items" -gt 0 ]; then
            pending_targets+=("$target")
            echo "  ${target}: ${pending_items} item(s) to transfer"
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
        # No --checksum: size+mtime skip is enough here (the plan above
        # already selected the targets, and STEP 3 hashes everything as
        # the integrity gate).
        rsync -a --info=progress2 \
            "${rsync_excludes[@]}" \
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
        "${rsync_excludes[@]}" \
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
    echo ""
    echo "Note: the plan and the transfer compare size+mtime, so a file"
    echo "whose size and date match but whose content does not is only"
    echo "caught here. To fix: delete the file(s) listed above from the"
    echo "destination, then re-run the script."
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
