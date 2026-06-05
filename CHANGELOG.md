# Changelog

All notable changes to Evo-SHAVE are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [V4.2026.06.05] - 2026-06-05

### Added

#### `workflow/rules/bam_barrier.smk` — Barrier rule before variant calling (new file)

A `localrule` that creates `flags/all_bams_ready.flag` once all per-sample deduplicated BAMs and their indices exist. `HaplotypeCaller` and `unifiedgenotyper` declare this flag as an input, preventing any variant-calling job from being submitted to SLURM before the entire BAM production phase completes. This avoids flooding the `long` partition queue with tens of thousands of jobs while `fast` partition BAM jobs are still pending — the root cause of rapid FairShare depletion.

#### `profile/config.yaml` — Priority directives on BAM-producing rules

`priority:` added to the four BAM-production rules so that Snakemake schedules them preferentially when multiple independent jobs are ready simultaneously:

| Rule | Priority |
|---|---|
| `bwa_mem` | 85 |
| `trimmomatic` | 80 |
| `merge_bams` | 75 |
| `markduplicates_bam` | 70 |
| `all_bams_ready` | — (localrule) |
| `HaplotypeCaller` / `unifiedgenotyper` | 0 (default) |

#### `analyze_efficiency.py` — SLURM job efficiency analyser (new file)

Post-pipeline script that parses `Cluster_logs/*.out` to extract SLURM job IDs and their associated Snakemake rules, queries `sacct` in a single batch call, and produces:

- Per-rule summary table: P50/P95 memory and runtime, CPU efficiency
- Top N memory outliers per rule
- Suggested resource floors for `profile/config.yaml`
- `profile/config_optimized.yaml` with updated floor values and traceability comments

CLI options: `--mem-margin`, `--time-margin`, `--n-outliers`, `--variability-thresh`, `--profile`, `--output`.

#### `analyze_efficiency.sh` — Wrapper for analyze_efficiency.py (new file)

Bash wrapper that loads `module load reportseff/2.7.6` and `module load conda` before calling `analyze_efficiency.py`. Usage: `bash analyze_efficiency.sh Cluster_logs/evoshave-*.out`.

#### `monitor_memory.sh` — Live memory monitoring via sstat (new file)

Polls `sstat` every N seconds during pipeline execution to capture peak `MaxRSS` per running SLURM job. Maps job IDs back to Snakemake rules from the `Cluster_logs/*.out` files. Outputs a TSV (`memory_log.tsv`) for post-run analysis. Required because the cluster does not populate `MaxRSS` in `sacct` — `sstat` must be queried while jobs are running.

Usage: `bash monitor_memory.sh --interval 60 --output memory_log.tsv`

#### `slurm_priority_diagnostic.md` — SLURM priority diagnostic guide (new file)

Reference document covering `squeue`, `sprio`, `sshare`, and `scontrol` commands for diagnosing PENDING jobs. Explains `LevelFS` interpretation, the compound FairShare penalty (account level × user level), and a decision tree for choosing between waiting, switching accounts, or requesting an admin boost.

### Changed

#### `profile/config.yaml` — Runtime floors reduced (calibrated from observed P95 data)

All runtime floors updated from `analyze_efficiency.py` results (run 2026-06-05, P95 × 1.5 margin):

| Rule | Before | After |
|---|---|---|
| `HaplotypeCaller` | `attempt * 180` min | `attempt * 30` min |
| `trimmomatic` | `max(..., 300)` min | `max(..., 30)` min |
| `bwa_mem` | `max(..., 120)` min | `max(..., 30)` min |
| `markduplicates_bam` | `max(..., 120)` min | `max(..., 20)` min |
| `samtools_index` | `max(..., 120)` min | `max(..., 15)` min |
| `samtools_stats_HC` | `attempt * 120` min | `attempt * 20` min |
| `qualimap_hc` | `attempt * 720` min | `attempt * 30` min |
| `validatesam_HC` | `max(..., 60)` min | `max(..., 15)` min |
| `genomics_db_import` | `attempt * 14400` min | `attempt * 720` min |
| `genotype_gvcfs` | `attempt * 2880` min | `attempt * 360` min |

#### `profile/config.yaml` — Memory floors reduced (obvious over-provisioning)

Memory floor values reduced for rules where the previous values were far above typical usage. To be re-calibrated with `monitor_memory.sh` on the next run:

| Rule | Before | After |
|---|---|---|
| `HaplotypeCaller` | 32 000 MB | 8 000 MB |
| `genotype_gvcfs` | 128 000 MB | 16 000 MB |
| `genomics_db_import` | 24 000 MB | 8 000 MB |
| `markduplicates_bam` | 16 000 MB | 4 000 MB |
| `bwa_mem` | 16 000 MB | 8 000 MB |
| `validatesam_HC` | 16 000 MB | 4 000 MB |

#### `workflow/rules/create_directories.smk` — Added `flags/` directory

`flags/` added to the `mkdir -p` call so that `all_bams_ready.flag` has a parent directory on first run.

#### `workflow/Snakefile` — Updated includes and localrules

- `include: "rules/bam_barrier.smk"` added after `common.smk`
- `all_bams_ready` added to `localrules`

---

## [V4.2026.06.03] - 2026-06-03

### Fixed

#### `Start_shave.sh` — FastQ file renaming

The rename function only handled a single input format (`.fq.gz` with lane identifier and numeric read number). It failed silently on all other formats.

- Both `.fq.gz` and `.fastq.gz` input extensions are now handled
- Automatic insertion of `_L1` for files without a lane identifier (common for single-lane sequencing runs or deliveries without lane information)
- Read number normalisation: accepts `1`/`2` and `R1`/`R2` on input, always produces `_R1`/`_R2`
- Sample names containing underscores (e.g. `Del_leu`) are now preserved — the previous `cut -d'_' -f1` logic truncated such names
- Files already in the correct `{sample}_L{n}_R{1|2}.fastq.gz` format are skipped (avoids reprocessing already-renamed files)
- On filename conflict (destination already exists): explicit warning and the duplicate is renamed to `{name}_dup{n}.fastq.gz` to prevent data loss

#### `workflow/rules/common.smk` — BWA read group tags

The `@RG ID` tag was identical for all lanes of the same sample (`ID:{sample}`). After merging multi-lane BAMs, reads from different lanes were indistinguishable.

- `ID`: `{sample}` → `{sample}_{unit}` (e.g. `AGS.2_L1`, `AGS.2_L8`) — each lane now has a unique identifier
- Added `LB:{sample}` (library) tag — used by Picard MarkDuplicates to correctly detect optical duplicates across lanes from the same library preparation

#### `Start_shave.sh` — Snakemake output routing

Snakemake writes its progress to stderr by default; all pipeline output was ending up in the SLURM `.err` log file while `.out` only contained the `echo` statements.

- Added `2>&1` to all `snakemake` calls so that progress, job statuses and warnings are routed to `.out`
- Exception: `--dag`/`--rulegraph`/`--filegraph` commands pipe stdout to `dot` — stderr is discarded (`2>/dev/null`) to prevent DOT format corruption
- Added `export PYTHONWARNINGS="ignore::UserWarning:pkg_resources"` to suppress the `pkg_resources` deprecation warning caused by setuptools ≥ 81 with Snakemake 8.x

### Changed

#### `Start_shave.sh` — Snakemake version

- Updated to `snakemake/8.27.1` (was `8.9.0`) — same major version, no breaking changes, resolves the `pkg_resources` warning at the source

#### `workflow/rules/common.smk` — Minimum version

- `min_version` updated to `"8.27.1"`

### Removed

- `get_bam_list()` in `workflow/rules/common.smk`: dead code, never called, duplicate of `get_input()` in `merge_bams.smk`

### Added

#### `config/config.yaml` — MarkDuplicates skip option

```yaml
markdup:
  skip: false   # Set to true for ddRAD-seq data
  remove-duplicates: false
```

In ddRAD-seq, reads systematically share the same start coordinates (enzymatic digestion). Picard MarkDuplicates would incorrectly flag the vast majority of reads as duplicates, severely reducing effective coverage. Setting `skip: true` bypasses this step.

#### `workflow/rules/markduplicates.smk` — Conditional passthrough rule

When `markdup.skip: true` is set:

- A substitute `markduplicates_bam` rule copies `merged/{sample}_merged.bam` directly to `dedup/{sample}_sorted_md.bam`
- An empty metrics placeholder is created (`qc/markdup/{sample}_sorted_md_metrics.txt`) so that MultiQC does not block
- All downstream rules (`HaplotypeCaller`, `SetNmMdAndUqTags`, `samtools_index`, `samtools_stats`, `validatesam`, `qualimap`, `multiqc`) work without modification

---

## [V4.2026.06.04] - 2026-06-04

### Fixed

#### `Start_shave.sh` — Conda environments removed on every run

`--conda-cleanup-envs` was called on every pipeline launch, removing environments that Snakemake considered orphaned after workflow changes (new rules, hash changes). Environments were deleted and then rebuilt at the next run, wasting 20–30 minutes each time. Step is now commented out and documented as a manual maintenance command.

#### `Start_shave.sh` / `profile/config.yaml` — Deprecated `--conda-frontend` warning

`--conda-frontend mamba` triggered a deprecation warning in Snakemake 8.27+: conda now embeds libmamba natively and ignores the frontend setting. Removed from all `snakemake` calls in `Start_shave.sh` and from `profile/config.yaml`.

#### `Start_shave.sh` — Conda temp file crash on compute nodes

`FileNotFoundError: [Errno 2] No such file or directory: '/tmp/slurm_ltalignani_*.tmp/tmp*.yaml'` — Snakemake's conda deployment code creates a temp yaml file using Python's `tempfile` (which respects `TMPDIR`). SLURM sets `TMPDIR` to a per-job local directory that is cleaned up before Snakemake's `os.remove()` call, causing a crash. Fixed by exporting `TMPDIR` to a stable shared path before any snakemake calls.

#### `workflow/rules/common.smk` — Numeric sample names parsed as integers

Sample names composed entirely of digits (e.g. `109`) were inferred as `int64` by pandas, causing `"|".join(samples.index)` in `wildcard_constraints` to raise `TypeError`. Added `dtype=str` to the `pd.read_table` call for `samples`.

#### `workflow/rules/gtgvcfs.smk` — `intervals` treated as input file

`intervals=lambda wildcards: wildcards.chrom` declared under `input:` caused Snakemake to treat the chromosome name as a required file path. Moved to `params:`, shell command updated to `{params.intervals}`.

#### `workflow/rules/gtgvcfs.smk` — Wrong conda environment path

`conda: "envs/gatk4.yaml"` resolved to `workflow/rules/envs/gatk4.yaml` (non-existent). Fixed to `"../envs/gatk4.yaml"`.

### Changed

#### `Start_shave.sh` — Dry-run now optional

A `dry_run` variable (line 58, default `"true"`) controls whether the pre-flight dry-run is executed. Set to `"false"` to skip it on large datasets (many samples or highly fragmented genomes) where DAG construction alone can be slow. Documented in `README.md`.

---

## [V4.2026.06.03b] - 2026-06-03

### Fixed

#### `workflow/rules/common.smk` — Numeric sample names parsed as integers

Sample names composed entirely of digits (e.g. `109`) were inferred as `int64` by pandas, causing `"|".join(samples.index)` in `wildcard_constraints` to raise `TypeError: sequence item 0: expected str instance, int found`. Added `dtype=str` to the `pd.read_table` call for `samples` (already present for `units`).

#### `workflow/rules/gtgvcfs.smk` — `intervals` treated as input file

`intervals=lambda wildcards: wildcards.chrom` was declared under `input:`, causing Snakemake to treat the chromosome name as a required file path and raise `MissingInputException`. Moved to `params:` and updated the shell command from `{input.intervals}` to `{params.intervals}`.

#### `workflow/rules/gtgvcfs.smk` — Wrong conda environment path

`conda: "envs/gatk4.yaml"` resolved relative to `workflow/rules/`, producing `workflow/rules/envs/gatk4.yaml` (non-existent). Fixed to `"../envs/gatk4.yaml"` consistent with all other rules.

### Changed

#### `Start_shave.sh` — conda frontend switched to mamba

All `--conda-frontend conda` flags replaced with `--conda-frontend mamba` to speed up environment resolution (5–10× faster dependency solving).

### Added

#### `workflow/rules/filter_vcf.smk` — Hard filtering pipeline (new file)

Full GATK Best Practices hard-filtering chain for both HaplotypeCaller and UnifiedGenotyper outputs:

- `select_snvs` / `select_indels` — extract SNV and indel variants separately
- `filter_snvs` / `filter_indels` — apply thresholds from `config.yaml filtering.hard`
- `select_pass_snvs` / `select_pass_indels` — retain PASS variants only
- `merge_filtered_vcf` — recombine into `calls/all.{chrom}.filtered.vcf.gz`; output marked `temp()` automatically when `vcf_output: "merged"`

#### `workflow/rules/bcftools_stats.smk` — VCF QC with bcftools (new file)

- `bcftools_stats_raw` — per-chromosome stats on raw (pre-filter) VCF
- `bcftools_stats_filtered` — per-chromosome stats on filtered VCF
- `bcftools_concat` — genome-wide filtered VCF via `bcftools concat -a -D`
- `bcftools_stats_genome` — genome-wide stats for MultiQC integration
- Concat and genome-wide rules skipped automatically when `vcf_output: "per_contig"`

#### `config/config.yaml` — Chromosome auto-detection

Replaced the flat `chromosomes:` list with a structured section:

```yaml
chromosomes:
  auto: false       # true = read contigs from .fai at parse time
  min_size: 0       # filter scaffolds below this size in bp
  pattern: ""       # regex filter on contig names (e.g. "^NC_")
  list:             # used when auto: false
    - "NC_085136.1"
  vcf_output: "both"  # "per_contig" | "merged" | "both"
```

Backwards-compatible: existing plain lists still work. Auto-detection reads the reference `.fai` at parse time — no checkpoint needed. Raises a clear error if filters produce an empty contig list.

#### `config/config.yaml` — VCF output mode

`vcf_output` under `chromosomes:` controls whether per-chromosome VCFs, a merged genome-wide VCF, or both are produced as final outputs. In `"merged"` mode, per-chromosome intermediates are automatically marked `temp()`.

#### `config/config.yaml` — Results transfer section

```yaml
transfer:
  results_dir: "/shared/projects/invalbo/results"
  run_name: "evo-shave"
```

#### `transfer_results.sh` — Automated results archiving (new file)

SLURM job (12 h, `long` partition) that:

1. Transfers all output directories to `{results_dir}/{run_name}_{YYYY-MM-DD}/` via `rsync --checksum`
2. Verifies the transfer with a dry-run checksum pass — aborts with `exit 1` on any mismatch
3. Deletes source outputs only after successful verification
4. Preserves `raw/`, `.snakemake/`, `config/`, `workflow/`, `resources/`, `profile/` and recreates an empty `Cluster_logs/`

`Start_shave.sh` prints a reminder to run `sbatch transfer_results.sh` at the end of each pipeline run.

#### MultiQC VCF QC integration

`bcftools stats` outputs (pre-filter per chrom, post-filter per chrom, genome-wide) added to inputs of both `multiqc` (UG) and `multiqc_HC` rules. Genome-wide stat omitted automatically when `vcf_output: "per_contig"`.

#### `workflow/rules/vcf_stats.smk` — Now runs on filtered VCF

VCFtools stats (`rule vcf_stats`) input updated from `rules.bgzip.output` to `calls/all.{chrom}.filtered.vcf.gz` so that reported metrics reflect the final filtered callset.

#### `workflow/Snakefile` — Refactored `rule all`

`_vcf_outputs` and `_vcf_qc` target lists pre-computed at parse time based on `vcf_output_mode`, then referenced in both HC and UG `rule all` branches. Eliminates duplicated expand() calls and makes the output mode logic explicit.

---

## [V3.2025.01.30] - 2025-01-30

- Added `merge_bams` rule: multi-lane BAM merging via Picard MergeSamFiles, simple copy if only one BAM unit
- Updated SLURM resource settings (`profile/config.yaml`): switched to `long` partition, adjusted memory and runtime allocations
- Added `parse_stats_data.py` script: consolidates samtools and qualimap statistics into a single CSV file
