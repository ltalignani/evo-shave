#!/bin/bash
# analyze_efficiency.sh — SLURM job efficiency analyzer for Evo-SHAVE
#
# Run after the pipeline completes to analyze CPU/memory usage per rule
# and generate an optimized profile/config.yaml.
#
# Usage:
#   bash analyze_efficiency.sh [--mem-margin 1.3] [--time-margin 1.5] \
#        [--n-outliers 5] Cluster_logs/evoshave-*.out
#
# Output:
#   - Efficiency report printed to stdout
#   - profile/config_optimized.yaml with updated resource floor values
#   - Review changes: diff profile/config.yaml profile/config_optimized.yaml

set -euo pipefail

module purge
module load reportseff/2.7.6   # provides reportseff for standalone display if needed
module load conda               # ensures python3 is available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "${SCRIPT_DIR}/analyze_efficiency.py" "$@"
