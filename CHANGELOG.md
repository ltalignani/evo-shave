# Changelog

All notable changes to SHAVE are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

## [V3.2025.01.30] - 2025-01-30

- Added `merge_bams` rule: multi-lane BAM merging via Picard MergeSamFiles, simple copy if only one BAM unit
- Updated SLURM resource settings (`profile/config.yaml`): switched to `long` partition, adjusted memory and runtime allocations
- Added `parse_stats_data.py` script: consolidates samtools and qualimap statistics into a single CSV file
