#!/bin/bash
#SBATCH -A invalbo
#SBATCH --job-name=conda-rebuild
#SBATCH --time=08:00:00
#SBATCH -p fast
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task 8
#SBATCH --mem=16G
#SBATCH -o Cluster_logs/%x-%j-%N.out
#SBATCH -e Cluster_logs/%x-%j-%N.err
#SBATCH --mail-user=loic.talignani@ird.fr
#SBATCH --mail-type=END,FAIL

# Rebuild corrupted/incomplete Snakemake conda environments
# USAGE: sbatch rebuild_conda_env.sh

module purge
module load snakemake/9.4.0
module load conda

umask 002

workdir=$(pwd)

export PYTHONWARNINGS="ignore::UserWarning:pkg_resources"
export TMPDIR=/shared/projects/invalbo/tmp/
mkdir -p ${TMPDIR}

# Fix curl SSL error 77: bioconductor post-link scripts use the conda env's cacert.pem
# which can be truncated. Force curl to use the system CA bundle instead.
SYSTEM_CACERT=""
for f in /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
    if [ -f "$f" ]; then
        SYSTEM_CACERT="$f"
        break
    fi
done
if [ -n "${SYSTEM_CACERT}" ]; then
    export CURL_CA_BUNDLE="${SYSTEM_CACERT}"
    export SSL_CERT_FILE="${SYSTEM_CACERT}"
    echo "Using system CA bundle: ${SYSTEM_CACERT}"
else
    echo "WARNING: no system CA bundle found — curl may fail with error 77"
fi

echo "Workdir: ${workdir}"
echo ""

# Remove all corrupted environment directories (trailing underscore = incomplete build)
# This catches any env truncated mid-install, regardless of hash.
echo "Removing incomplete conda environments..."
find "${workdir}/.snakemake/conda/" -maxdepth 1 -type d -name '*_' -print -exec rm -rf {} + 2>/dev/null
echo "Done."
echo ""

echo "Creating all conda environments..."
snakemake \
    --workflow-profile profile/cluster \
    --directory "${workdir}/" \
    --cores 8 \
    --conda-create-envs-only \
    2>&1

echo ""
echo "Conda env rebuild complete."
