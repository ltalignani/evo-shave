#!/bin/bash
# monitor_memory.sh — Live memory monitoring for running SLURM jobs
#
# Polls sstat every N seconds and logs MaxRSS per job, grouped by Snakemake rule.
# Run this WHILE the pipeline is executing to capture peak memory per rule.
#
# Usage:
#   bash monitor_memory.sh [--interval 30] [--output memory_log.tsv]
#
# Output columns: timestamp, slurm_jobid, rule, wildcards, MaxRSS_MB, AllocMem_MB
#
# After the run, summarize with:
#   awk -F'\t' 'NR>1 {sum[$3]+=$5; count[$3]++; if($5>max[$3]) max[$3]=$5}
#               END {for(r in max) print r, "max="max[r]"MB", "mean="sum[r]/count[r]"MB"}' memory_log.tsv

set -euo pipefail

INTERVAL=30
OUTPUT="memory_log.tsv"
LOG_PATTERN="Cluster_logs/evoshave-*.out"

while [[ $# -gt 0 ]]; do
    case $1 in
        --interval) INTERVAL=$2; shift 2 ;;
        --output)   OUTPUT=$2;   shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Starting memory monitor (interval=${INTERVAL}s, output=${OUTPUT})"
echo "Stop with Ctrl+C"
echo ""

# Write header
echo -e "timestamp\tslurm_jobid\trule\twildcards\tMaxRSS_MB\tAllocMem_MB" > "${OUTPUT}"

# Build rule/wildcard lookup from existing logs
declare -A JOB_RULE
declare -A JOB_WILDCARDS

reload_job_map() {
    while IFS= read -r line; do
        if [[ "$line" =~ "submitted with SLURM jobid" ]]; then
            slurm_id=$(echo "$line" | grep -oE 'jobid [0-9]+' | awk '{print $2}')
            rule=$(echo "$line" | grep -oE 'rule_[A-Za-z_]+' | sed 's/rule_//')
            wildcards=$(echo "$line" | grep -oE 'rule_[A-Za-z_]+/[^/]+' | sed 's|rule_[A-Za-z_]+/||')
            if [[ -n "$slurm_id" ]]; then
                JOB_RULE[$slurm_id]="$rule"
                JOB_WILDCARDS[$slurm_id]="$wildcards"
            fi
        fi
    done < <(cat ${LOG_PATTERN} 2>/dev/null)
}

parse_mem_mb() {
    local mem="$1"
    mem="${mem%c}"
    mem="${mem%n}"
    if [[ "$mem" =~ ^([0-9.]+)K$ ]]; then echo "$(echo "${BASH_REMATCH[1]} / 1024" | bc -l | xargs printf '%.0f')"; return; fi
    if [[ "$mem" =~ ^([0-9.]+)M$ ]]; then echo "${BASH_REMATCH[1]%.*}"; return; fi
    if [[ "$mem" =~ ^([0-9.]+)G$ ]]; then echo "$(echo "${BASH_REMATCH[1]} * 1024" | bc -l | xargs printf '%.0f')"; return; fi
    echo "0"
}

while true; do
    reload_job_map

    # Get all running jobs (exclude evoshave master)
    running_ids=$(squeue --me -h -o "%i %j" | awk '$2 != "evoshave" {print $1}')

    if [[ -z "$running_ids" ]]; then
        echo "$(date '+%H:%M:%S') — no running jobs"
        sleep "${INTERVAL}"
        continue
    fi

    ids_csv=$(echo "$running_ids" | tr '\n' ',' | sed 's/,$//')

    # Query sstat for all running jobs at once
    sstat_output=$(sstat --parsable2 --noheader \
        --format=JobID,MaxRSS,ReqMem \
        --jobs="${ids_csv}" 2>/dev/null || true)

    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    count=0

    while IFS='|' read -r job_id max_rss req_mem; do
        [[ "$job_id" =~ \. ]] && continue  # skip .batch sub-steps
        [[ -z "$max_rss" || "$max_rss" == "0" ]] && continue

        rule="${JOB_RULE[$job_id]:-unknown}"
        wildcards="${JOB_WILDCARDS[$job_id]:-unknown}"
        rss_mb=$(parse_mem_mb "$max_rss")
        alloc_mb=$(parse_mem_mb "$req_mem")

        echo -e "${ts}\t${job_id}\t${rule}\t${wildcards}\t${rss_mb}\t${alloc_mb}" >> "${OUTPUT}"
        ((count++))
    done <<< "$sstat_output"

    echo "$(date '+%H:%M:%S') — sampled ${count} running jobs → ${OUTPUT}"
    sleep "${INTERVAL}"
done
