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

# USAGE:
#   Cluster : sbatch run_shave.sh
#   Local   : bash run_shave.sh

# ── User-tunable parameters ────────────────────────────────────────────────────
# Maximum local cores (auto-detected below; override here if needed)
LOCAL_CORES_CAP=16
# Set to "true" to create/refresh conda environments before the run
CREATE_ENVS="false"
# Set to "true" to perform a dry-run only
DRY_RUN="false"
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

workdir=$(pwd)

# ── Environment detection ──────────────────────────────────────────────────────
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    ENV="cluster"
elif [[ "$(uname -m)" == "arm64" ]]; then
    ENV="local_mac"
else
    ENV="local_linux"
fi

echo ""
echo "------------------------------------------------------------------------"
echo "##### ABOUT #####"
echo "------------------------------------------------------------------------"
echo ""
echo "Name __________________ run_shave.sh"
echo "Author ________________ Loïc Talignani"
echo "Affiliation ___________ UMR_MIVEGEC"
echo "Aim ___________________ SHort-read Alignment pipeline for VEctors"
echo "Detected environment __ ${ENV}"
echo "Workdir _______________ ${workdir}"

# ── Environment-specific setup ────────────────────────────────────────────────
case "${ENV}" in

  cluster)
    SNAKEMAKE_PROFILE="profile/cluster"
    SNAKEMAKE_EXTRA="--executor slurm --jobs 500 --retries 5 --local-cores 8"

    module purge
    module load snakemake/9.4.0
    module load conda
    SNAKEMAKE_CMD="snakemake"

    export PYTHONWARNINGS="ignore::UserWarning:pkg_resources"
    export XDG_CACHE_HOME=/shared/projects/invalbo/ev-shave/
    export TMPDIR=/shared/projects/invalbo/tmp/
    mkdir -p "${TMPDIR}"
    umask 002
    ;;

  local_mac)
    SNAKEMAKE_PROFILE="profile/local"
    # Detect available cores; cap at LOCAL_CORES_CAP
    _ncpu=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    LOCAL_CORES=$(( _ncpu < LOCAL_CORES_CAP ? _ncpu : LOCAL_CORES_CAP ))
    SNAKEMAKE_EXTRA="--cores ${LOCAL_CORES}"

    # Force conda to use osx-64 packages (Rosetta 2) for broadest bioconda compatibility
    export CONDA_SUBDIR=osx-64
    export TMPDIR="${TMPDIR:-/tmp}/shave"
    mkdir -p "${TMPDIR}"

    # If CONDA_EXE is set (by conda init), prioritize its directory in PATH so
    # snakemake subprocesses find the correct conda and not a broken alternative.
    if [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE}" ]]; then
        export PATH="$(dirname "${CONDA_EXE}"):${PATH}"
    fi

    # Prefer the local .env if it exists
    if [[ -x "${workdir}/.env/bin/snakemake" ]]; then
        SNAKEMAKE_CMD="${workdir}/.env/bin/snakemake"
    else
        SNAKEMAKE_CMD="snakemake"
    fi
    ;;

  local_linux)
    SNAKEMAKE_PROFILE="profile/local"
    _ncpu=$(nproc 2>/dev/null || echo 4)
    LOCAL_CORES=$(( _ncpu < LOCAL_CORES_CAP ? _ncpu : LOCAL_CORES_CAP ))
    SNAKEMAKE_EXTRA="--cores ${LOCAL_CORES}"

    export TMPDIR="${TMPDIR:-/tmp}/shave"
    mkdir -p "${TMPDIR}"

    if [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE}" ]]; then
        export PATH="$(dirname "${CONDA_EXE}"):${PATH}"
    fi

    if [[ -x "${workdir}/.env/bin/snakemake" ]]; then
        SNAKEMAKE_CMD="${workdir}/.env/bin/snakemake"
    else
        SNAKEMAKE_CMD="snakemake"
    fi
    ;;
esac

# ── Preflight checks ───────────────────────────────────────────────────────────
echo ""
echo "Running preflight checks..."

# Snakemake ≥ 9
if ! command -v "${SNAKEMAKE_CMD}" &>/dev/null; then
    echo "ERROR: snakemake not found at '${SNAKEMAKE_CMD}'."
    echo "       On local: create .env with 'python -m venv .env && .env/bin/pip install -r requirements.txt'"
    exit 1
fi
_smk_version=$("${SNAKEMAKE_CMD}" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [[ "${_smk_version:-0}" -lt 9 ]]; then
    echo "ERROR: Snakemake ≥ 9 required, found $("${SNAKEMAKE_CMD}" --version 2>/dev/null)."
    exit 1
fi
echo "  snakemake $("${SNAKEMAKE_CMD}" --version) ... OK"

# conda
if ! command -v conda &>/dev/null; then
    echo "ERROR: conda not found. Install Miniforge or Mambaforge."
    exit 1
fi
echo "  conda $(conda --version 2>/dev/null) ... OK"

# graphviz (optional)
if command -v dot &>/dev/null; then
    HAVE_DOT=true
    echo "  graphviz (dot) ... OK"
else
    HAVE_DOT=false
    echo "  graphviz (dot) ... NOT FOUND (graphs will be skipped)"
    echo "    Install: brew install graphviz  [Mac] | apt install graphviz  [Linux]"
    echo "    Or: pip install graphviz  (Python binding, adds 'dot' to .env)"
fi

# ── Rename FastQ files ─────────────────────────────────────────────────────────
echo ""
echo "------------------------------------------------------------------------"
echo "RENAME FASTQ FILES"
echo "------------------------------------------------------------------------"
echo ""

input_directory="raw"

for file in "$input_directory"/*.fq.gz "$input_directory"/*.fastq.gz; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")

    if [[ "$filename" =~ ^.+_L[0-9]+_R[12]\.fastq\.gz$ ]]; then
        echo "File OK : $filename"
        continue
    fi

    base="${filename%.fq.gz}"
    base="${base%.fastq.gz}"
    read_part="${base##*_}"

    case "$read_part" in
        1|R1) fastq_read="R1" ;;
        2|R2) fastq_read="R2" ;;
        *)
            echo "WARN: Cannot determine read number for $filename — skipped"
            continue
            ;;
    esac

    prefix_lane="${base%_${read_part}}"
    lane=$(echo "$prefix_lane" | grep -oE '_L[0-9]+' | tail -1 | sed 's/^_//')

    if [ -n "$lane" ]; then
        prefix="${prefix_lane%_${lane}}"
    else
        lane="L1"
        prefix="$prefix_lane"
    fi

    new_filename="${prefix}_${lane}_${fastq_read}.fastq.gz"

    if [ -f "$input_directory/$new_filename" ]; then
        counter=1
        while [ -f "$input_directory/${prefix}_${lane}_${fastq_read}_dup${counter}.fastq.gz" ]; do
            ((counter++))
        done
        dup_filename="${prefix}_${lane}_${fastq_read}_dup${counter}.fastq.gz"
        echo "WARN: $new_filename already exists — renaming $filename to $dup_filename"
        mv "$file" "$input_directory/$dup_filename"
    else
        mv "$file" "$input_directory/$new_filename"
        echo "Renamed: $filename -> $new_filename"
    fi
done

# ── Create directories ─────────────────────────────────────────────────────────
# Only Cluster_logs/ is created here — it must exist before Snakemake starts,
# since SLURM writes %x-%j-%N.out/.err there from job submission onward.
# Every other directory is created by the Snakemake `create_directories` rule
# (workflow/rules/create_directories.smk), which is prioritized to run first
# (--prioritize create_directories, below). Keeping directory lists in one
# place (the rule) avoids the two copies drifting apart.
mkdir -p Cluster_logs/

# ── Unlock if needed ───────────────────────────────────────────────────────────
if [ -n "$(ls "${workdir}/.snakemake/locks/" 2>/dev/null)" ]; then
    echo ""
    echo "Unlocking working directory..."
    "${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" --directory "${workdir}/" --unlock 2>&1
else
    echo "No lock file found — skipping unlock."
fi

# ── Conda env creation (optional) ─────────────────────────────────────────────
echo ""
echo "Conda environments:"
echo ""

if [ "${CREATE_ENVS}" == "true" ]; then
    "${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
        --directory "${workdir}/" \
        --keep-going --rerun-incomplete \
        --conda-create-envs-only \
        ${SNAKEMAKE_EXTRA} 2>&1
else
    echo "Skipping conda env creation (set CREATE_ENVS=true to force rebuild)."
fi

# ── Dry-run ────────────────────────────────────────────────────────────────────
if [ "${DRY_RUN}" == "true" ]; then
    echo ""
    echo "------------------------------------------------------------------------"
    echo "DRY RUN"
    echo "------------------------------------------------------------------------"
    echo ""
    "${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
        --directory "${workdir}/" \
        --keep-going --rerun-incomplete \
        --prioritize create_directories \
        --dry-run \
        ${SNAKEMAKE_EXTRA} 2>&1
    exit 0
fi

# ── Pipeline execution ────────────────────────────────────────────────────────
echo ""
echo "------------------------------------------------------------------------"
echo "SNAKEMAKE PIPELINE START"
echo "------------------------------------------------------------------------"
echo ""

"${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
    --directory "${workdir}/" \
    --keep-going --rerun-incomplete \
    --prioritize create_directories \
    ${SNAKEMAKE_EXTRA} 2>&1

# ── Post-run: graphs, summary, report ─────────────────────────────────────────
echo ""
echo "------------------------------------------------------------------------"
echo "POST-RUN"
echo "------------------------------------------------------------------------"
echo ""

# Load graphviz module on cluster if needed
if [[ "${ENV}" == "cluster" ]]; then
    module load graphviz/2.40.1 2>/dev/null || true
fi

mkdir -p "${workdir}/graphs/"

if [[ "${HAVE_DOT}" == true ]]; then
    for graph in dag rulegraph filegraph; do
        for ext in pdf png; do
            "${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
                --keep-going --rerun-incomplete \
                --directory "${workdir}/" \
                --${graph} 2>/dev/null \
            | dot -T${ext} > "${workdir}/graphs/${graph}.${ext}" \
            && echo "  ${graph}.${ext} generated" \
            || echo "  WARN: ${graph}.${ext} failed"
        done
    done
else
    echo "graphviz not available — skipping graph generation."
fi

"${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
    --keep-going --rerun-incomplete \
    --directory "${workdir}" \
    --summary > "${workdir}/files_summary.txt" 2>&1
echo "Summary written to: files_summary.txt"

echo ""
echo "Generating Snakemake HTML report..."
"${SNAKEMAKE_CMD}" --workflow-profile "${SNAKEMAKE_PROFILE}" \
    --directory "${workdir}/" \
    --report "${workdir}/snakemake_report.html" 2>&1
echo "Report written to: snakemake_report.html"

# ── Cleanup ────────────────────────────────────────────────────────────────────
find "${workdir}/logs/" -type f -empty -delete
find "${workdir}/" -type d -empty -delete 2>/dev/null || true

time_stamp_end=$(date +"%Y-%m-%d %H:%M")
minutes=$(( SECONDS / 60 ))
seconds=$(( SECONDS % 60 ))

echo ""
echo "------------------------------------------------------------------------"
echo "DONE"
echo "------------------------------------------------------------------------"
echo ""
echo "End Time ______________ ${time_stamp_end}"
echo "Processing Time _______ ${minutes} minutes and ${seconds} seconds"
echo ""
echo "------------------------------------------------------------------------"
echo "NEXT STEP — ARCHIVE RESULTS"
echo "------------------------------------------------------------------------"
echo ""
echo "  sbatch transfer_results.sh"
echo ""
echo "Edit transfer.results_dir and transfer.run_name in config/config.yaml"
echo "before running."
echo ""
