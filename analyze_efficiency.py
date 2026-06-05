#!/usr/bin/env python3
"""
analyze_efficiency.py — SLURM job efficiency analyzer for Evo-SHAVE

Parses Cluster_logs/*.out to extract SLURM job IDs, queries sacct for CPU/memory
metrics, aggregates by Snakemake rule, and generates an optimized profile/config.yaml
with updated resource floor values.

Usage (after pipeline completes):
    python analyze_efficiency.py Cluster_logs/evoshave-*.out [OPTIONS]

Options:
    --mem-margin FLOAT        Safety multiplier applied to P95 memory (default: 1.3)
    --time-margin FLOAT       Safety multiplier applied to P95 runtime (default: 1.5)
    --n-outliers INT          Top N jobs reported per rule (default: 5)
    --variability-thresh FLT  P95/P50 ratio above which high margin is used (default: 1.5)
    --profile PATH            Source profile/config.yaml (default: profile/config.yaml)
    --output PATH             Output path for optimized config (default: profile/config_optimized.yaml)
"""

import argparse
import math
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(
        description="Analyze SLURM job efficiency for Evo-SHAVE pipeline"
    )
    p.add_argument("log_files", nargs="+", help="Cluster_logs/*.out files to analyze")
    p.add_argument("--mem-margin", type=float, default=1.3,
                   help="Safety margin on P95 memory (default: 1.3)")
    p.add_argument("--time-margin", type=float, default=1.5,
                   help="Safety margin on P95 runtime (default: 1.5)")
    p.add_argument("--n-outliers", type=int, default=5,
                   help="Top N outliers reported per rule (default: 5)")
    p.add_argument("--variability-thresh", type=float, default=1.5,
                   help="P95/P50 ratio above which high margin is applied (default: 1.5)")
    p.add_argument("--profile", default="profile/config.yaml",
                   help="Source profile/config.yaml (default: profile/config.yaml)")
    p.add_argument("--output", default="profile/config_optimized.yaml",
                   help="Output path for optimized config (default: profile/config_optimized.yaml)")
    return p.parse_args()


# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

_LOG_PATTERN = re.compile(
    r"Job \d+ has been submitted with SLURM jobid (\d+)"
    r" \(log: .+/rule_(\w+)/(.+)/\d+\.log\)"
)


def parse_logs(log_files):
    """Return {slurm_id: {'rule': str, 'wildcards': str}} from Snakemake .out logs."""
    job_map = {}
    for path in log_files:
        with open(path) as fh:
            for line in fh:
                m = _LOG_PATTERN.search(line)
                if m:
                    slurm_id, rule, wildcards = m.groups()
                    job_map[slurm_id] = {"rule": rule, "wildcards": wildcards}
    return job_map


# ---------------------------------------------------------------------------
# sacct query
# ---------------------------------------------------------------------------

def _parse_elapsed(s):
    """Convert D-HH:MM:SS or HH:MM:SS to seconds. Returns None on failure."""
    if not s or s in ("None", ""):
        return None
    days = 0
    if "-" in s:
        d, s = s.split("-", 1)
        days = int(d)
    parts = s.split(":")
    try:
        if len(parts) == 3:
            h, m, sec = int(parts[0]), int(parts[1]), int(parts[2])
        elif len(parts) == 2:
            h, m, sec = 0, int(parts[0]), int(parts[1])
        else:
            return None
    except ValueError:
        return None
    return days * 86400 + h * 3600 + m * 60 + sec


def _parse_mem_mb(s):
    """Convert sacct memory strings (e.g. '32000Mc', '32Gn', '8192000K') to MB."""
    if not s or s in ("None", "0", ""):
        return None
    s = s.rstrip("cn")  # strip per-cpu / per-node suffix
    try:
        if s.endswith("K"):
            return float(s[:-1]) / 1024
        if s.endswith("M"):
            return float(s[:-1])
        if s.endswith("G"):
            return float(s[:-1]) * 1024
        if s.endswith("T"):
            return float(s[:-1]) * 1024 * 1024
        return float(s)
    except ValueError:
        return None


def get_sacct_data(job_ids):
    """
    Query sacct for a list of SLURM job IDs.
    Returns {job_id: {state, elapsed_s, elapsed_min, alloc_cpus, req_mem_mb,
                       max_rss_mb, cpu_eff}} for COMPLETED/FAILED/TIMEOUT jobs.
    """
    if not job_ids:
        return {}

    cmd = [
        "sacct", "--parsable2", "--noheader",
        "--format=JobIDRaw,State,Elapsed,AllocCPUS,ReqMem,MaxRSS,TotalCPU",
        f"--jobs={','.join(job_ids)}",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: sacct failed:\n{e.stderr}", file=sys.stderr)
        sys.exit(1)

    data = {}
    for line in result.stdout.splitlines():
        fields = line.split("|")
        if len(fields) < 7:
            continue
        job_id_raw, state, elapsed, alloc_cpus, req_mem, max_rss, total_cpu = fields[:7]

        if "." in job_id_raw:  # skip .batch / .extern sub-steps
            continue
        if state not in ("COMPLETED", "FAILED", "TIMEOUT"):
            continue

        elapsed_s = _parse_elapsed(elapsed)
        total_cpu_s = _parse_elapsed(total_cpu)
        req_mem_mb = _parse_mem_mb(req_mem)
        max_rss_mb = _parse_mem_mb(max_rss)

        try:
            n_cpus = int(alloc_cpus)
        except ValueError:
            n_cpus = 1

        cpu_eff = None
        if elapsed_s and total_cpu_s and n_cpus and elapsed_s > 0:
            cpu_eff = (total_cpu_s / (elapsed_s * n_cpus)) * 100

        data[job_id_raw] = {
            "state": state,
            "elapsed_s": elapsed_s,
            "elapsed_min": elapsed_s / 60 if elapsed_s else None,
            "alloc_cpus": n_cpus,
            "req_mem_mb": req_mem_mb,
            "max_rss_mb": max_rss_mb,
            "cpu_eff": cpu_eff,
        }

    return data


# ---------------------------------------------------------------------------
# Statistics helpers
# ---------------------------------------------------------------------------

def _sorted_values(items, key):
    return sorted((x[key] for x in items if x.get(key) is not None))


def _percentile(values, p):
    if not values:
        return None
    idx = (p / 100) * (len(values) - 1)
    lo, hi = int(idx), min(int(idx) + 1, len(values) - 1)
    return values[lo] * (1 - (idx - lo)) + values[hi] * (idx - lo)


def compute_rule_stats(jobs):
    mem = _sorted_values(jobs, "max_rss_mb")
    time = _sorted_values(jobs, "elapsed_min")
    cpu = _sorted_values(jobs, "cpu_eff")
    req = _sorted_values(jobs, "req_mem_mb")

    return {
        "n_jobs": len(jobs),
        "n_completed": sum(1 for j in jobs if j["state"] == "COMPLETED"),
        "n_failed": sum(1 for j in jobs if j["state"] == "FAILED"),
        "n_timeout": sum(1 for j in jobs if j["state"] == "TIMEOUT"),
        "mem_p50": _percentile(mem, 50),
        "mem_p95": _percentile(mem, 95),
        "mem_max": mem[-1] if mem else None,
        "req_mem_p50": _percentile(req, 50),
        "time_p50_min": _percentile(time, 50),
        "time_p95_min": _percentile(time, 95),
        "time_max_min": time[-1] if time else None,
        "cpu_eff_p50": _percentile(cpu, 50),
    }


# ---------------------------------------------------------------------------
# Resource suggestion
# ---------------------------------------------------------------------------

_MIN_MEM_MB = 4000
_MEM_ROUND = 1000
_TIME_ROUND = 10
_MIN_TIME_MIN = 10


def suggest_resources(stats, mem_margin, time_margin, variability_thresh):
    suggestions = {}

    if stats["mem_p95"] and stats["mem_p50"] and stats["mem_p50"] > 0:
        variability = stats["mem_p95"] / stats["mem_p50"]
        margin = time_margin if variability > variability_thresh else mem_margin
        raw = stats["mem_p95"] * margin
        suggestions["mem_mb"] = {
            "value": max(_MIN_MEM_MB, math.ceil(raw / _MEM_ROUND) * _MEM_ROUND),
            "p95_gb": stats["mem_p95"] / 1024,
            "current_mb": stats["req_mem_p50"],
            "margin": margin,
        }

    if stats["time_p95_min"] and stats["time_p50_min"] and stats["time_p50_min"] > 0:
        variability = stats["time_p95_min"] / stats["time_p50_min"]
        margin = time_margin if variability > variability_thresh else time_margin
        raw = stats["time_p95_min"] * margin
        suggestions["runtime"] = {
            "value": max(_MIN_TIME_MIN, math.ceil(raw / _TIME_ROUND) * _TIME_ROUND),
            "p95_min": stats["time_p95_min"],
            "margin": margin,
        }

    return suggestions


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def _fmt_mem(mb):
    if mb is None:
        return "N/A"
    return f"{mb/1024:.1f}G" if mb >= 1024 else f"{mb:.0f}M"


def _fmt_min(m):
    if m is None:
        return "N/A"
    h = int(m // 60)
    mm = int(m % 60)
    return f"{h}h{mm:02d}m" if h else f"{mm}m"


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def print_report(by_rule, stats_by_rule, suggestions_by_rule, sacct_data, job_map, args):
    W = 100
    print("=" * W)
    print("EVO-SHAVE — SLURM JOB EFFICIENCY REPORT")
    print("=" * W)

    total = sum(s["n_jobs"] for s in stats_by_rule.values())
    done = sum(s["n_completed"] for s in stats_by_rule.values())
    failed = sum(s["n_failed"] + s["n_timeout"] for s in stats_by_rule.values())

    print(f"\n  Log files  : {', '.join(str(f) for f in args.log_files)}")
    print(f"  Jobs found : {total}  (completed={done}, failed/timeout={failed})")
    print(f"  Mem margin : ×{args.mem_margin}  (×{args.time_margin} if P95/P50 > {args.variability_thresh})")
    print(f"  Time margin: ×{args.time_margin}")

    # Summary table
    COL = f"{'RULE':<32} {'N':>5} {'ERR':>4}  {'MEM_P50':>7} {'MEM_P95':>7} {'REQ_MEM':>7}  {'T_P50':>6} {'T_P95':>6}  {'CPU_EFF':>7}"
    print("\n" + "─" * W)
    print(COL)
    print("─" * W)

    for rule in sorted(by_rule.keys()):
        s = stats_by_rule[rule]
        err = s["n_failed"] + s["n_timeout"]
        cpu = f"{s['cpu_eff_p50']:.0f}%" if s["cpu_eff_p50"] is not None else "N/A"
        print(
            f"  {rule:<30} {s['n_jobs']:>5} {err if err else '-':>4}  "
            f"{_fmt_mem(s['mem_p50']):>7} {_fmt_mem(s['mem_p95']):>7} {_fmt_mem(s['req_mem_p50']):>7}  "
            f"{_fmt_min(s['time_p50_min']):>6} {_fmt_min(s['time_p95_min']):>6}  "
            f"{cpu:>7}"
        )

    print("─" * W)

    # Outliers
    print(f"\n{'=' * W}")
    print(f"TOP {args.n_outliers} MEMORY OUTLIERS PER RULE")
    print("=" * W)

    for rule in sorted(by_rule.keys()):
        jobs = by_rule[rule]
        top = sorted(
            [j for j in jobs if j.get("max_rss_mb")],
            key=lambda x: x["max_rss_mb"],
            reverse=True,
        )[: args.n_outliers]

        if not top:
            continue

        print(f"\n  {rule}:")
        for j in top:
            cpu_str = f"{j['cpu_eff']:.0f}%" if j.get("cpu_eff") is not None else "N/A"
            print(
                f"    [{j['state'][:4]}] {j['wildcards']:<52}"
                f"  mem={_fmt_mem(j['max_rss_mb']):<7}"
                f"  time={_fmt_min(j['elapsed_min']):<7}"
                f"  cpu={cpu_str}"
            )

    # Suggestions
    print(f"\n{'=' * W}")
    print("SUGGESTED CHANGES FOR profile/config.yaml  →  profile/config_optimized.yaml")
    print("=" * W)

    any_suggestion = False
    for rule in sorted(suggestions_by_rule.keys()):
        sug = suggestions_by_rule[rule]
        if not sug:
            continue
        any_suggestion = True
        print(f"\n  {rule}:")
        if "mem_mb" in sug:
            s = sug["mem_mb"]
            cur = _fmt_mem(s["current_mb"]) if s["current_mb"] else "unknown"
            print(
                f"    mem_mb floor : {cur:>8}  →  {_fmt_mem(s['value']):<8}"
                f"  (P95={s['p95_gb']:.2f} GB × {s['margin']})"
            )
        if "runtime" in sug:
            s = sug["runtime"]
            print(
                f"    runtime floor:           →  {s['value']} min"
                f"  (P95={s['p95_min']:.1f} min × {s['margin']})"
            )

    if not any_suggestion:
        print("\n  No changes needed — current allocations are well-calibrated.")

    print(f"\n  Optimized config written to : {args.output}")
    print(f"  Review with                 : diff {args.profile} {args.output}")
    print()


# ---------------------------------------------------------------------------
# Config update
# ---------------------------------------------------------------------------

def update_config(profile_path, suggestions_by_rule, output_path):
    """
    Write a copy of profile_path with updated resource floors in set-resources section.
    Preserves dynamic formulas; only updates the floor constant.
    Adds a comment with the observed P95 value for traceability.
    """
    with open(profile_path) as fh:
        lines = fh.readlines()

    output_lines = []
    in_set_resources = False
    current_rule = None

    for line in lines:
        stripped = line.lstrip()

        # Track set-resources section
        if line.startswith("set-resources:"):
            in_set_resources = True
            output_lines.append(line)
            continue
        if in_set_resources and line and not line[0].isspace():
            in_set_resources = False
            current_rule = None

        if in_set_resources:
            # Detect 2-space-indented rule name
            rule_match = re.match(r"^  (\w+):\s*$", line)
            if rule_match:
                current_rule = rule_match.group(1)
                output_lines.append(line)
                continue

            if current_rule and current_rule in suggestions_by_rule:
                sug = suggestions_by_rule[current_rule]

                # Update mem_mb floor inside max(..., FLOOR)
                if "mem_mb" in sug and re.search(r"mem_mb:", line):
                    s = sug["mem_mb"]
                    comment = f"  # observed P95: {s['p95_gb']:.2f} GB, margin ×{s['margin']}"
                    # Strip any existing trailing comment before rewriting
                    line_no_comment = re.sub(r"\s*#.*$", "", line.rstrip())
                    new_line = re.sub(
                        r"(max\([^,]+,\s*)(\d+)(\))",
                        lambda m: f"{m.group(1)}{s['value']}{m.group(3)}",
                        line_no_comment,
                    )
                    if new_line != line_no_comment:
                        output_lines.append(new_line + comment + "\n")
                        continue

                # Update runtime floor inside max(..., FLOOR)
                if "runtime" in sug and re.search(r"runtime:", line):
                    s = sug["runtime"]
                    comment = f"  # observed P95: {s['p95_min']:.1f} min, margin ×{s['margin']}"
                    line_no_comment = re.sub(r"\s*#.*$", "", line.rstrip())
                    # max(..., FLOOR) pattern
                    new_line = re.sub(
                        r"(max\([^,]+,\s*)(\d+)(\))",
                        lambda m: f"{m.group(1)}{s['value']}{m.group(3)}",
                        line_no_comment,
                    )
                    if new_line != line_no_comment:
                        output_lines.append(new_line + comment + "\n")
                        continue
                    # attempt * N pattern
                    new_line = re.sub(
                        r"(runtime:\s*attempt \* )(\d+)",
                        lambda m: f"{m.group(1)}{s['value']}",
                        line_no_comment,
                    )
                    if new_line != line_no_comment:
                        output_lines.append(new_line + comment + "\n")
                        continue

        output_lines.append(line)

    with open(output_path, "w") as fh:
        fh.writelines(output_lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    print("Parsing log files...", file=sys.stderr)
    job_map = parse_logs(args.log_files)
    print(f"  Found {len(job_map)} job submissions", file=sys.stderr)

    if not job_map:
        print("ERROR: No SLURM job IDs found in the provided log files.", file=sys.stderr)
        sys.exit(1)

    print("Querying sacct...", file=sys.stderr)
    sacct_data = get_sacct_data(list(job_map.keys()))
    print(f"  Got data for {len(sacct_data)} completed/failed jobs", file=sys.stderr)

    if not sacct_data:
        print(
            "ERROR: sacct returned no data. Jobs may still be running, or sacct\n"
            "       may not have records yet (try again after pipeline finishes).",
            file=sys.stderr,
        )
        sys.exit(1)

    # Merge sacct data with rule/wildcard info
    by_rule = defaultdict(list)
    for slurm_id, metrics in sacct_data.items():
        if slurm_id in job_map:
            by_rule[job_map[slurm_id]["rule"]].append(
                {"wildcards": job_map[slurm_id]["wildcards"], **metrics}
            )

    stats_by_rule = {rule: compute_rule_stats(jobs) for rule, jobs in by_rule.items()}
    suggestions_by_rule = {
        rule: suggest_resources(
            stats_by_rule[rule], args.mem_margin, args.time_margin, args.variability_thresh
        )
        for rule in by_rule
    }

    print_report(by_rule, stats_by_rule, suggestions_by_rule, sacct_data, job_map, args)

    profile = Path(args.profile)
    if profile.exists():
        update_config(profile, suggestions_by_rule, args.output)
    else:
        print(
            f"WARNING: {args.profile} not found — skipping config_optimized.yaml generation.",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
