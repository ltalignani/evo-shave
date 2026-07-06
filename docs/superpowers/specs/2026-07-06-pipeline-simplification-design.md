# Pipeline simplification: drop VCF report/bcftools stats and the UnifiedGenotyper path — design spec

Date: 2026-07-06

## Problem

The pipeline currently supports two variant callers (`HaplotypeCaller` and legacy
`UnifiedGenotyper`/GATK3 with indel realignment) and produces a VCF HTML report
(`report_vcf`) plus `bcftools stats` at every stage (raw, filtered, per-chrom,
genome-wide). Neither is used any more:

- The UnifiedGenotyper/GATK3 path (indel realignment, `unifiedgenotyper`,
  legacy fixmate/sort chain) is legacy and no longer needed — only the
  HaplotypeCaller path is used going forward.
- `report_vcf` (R/Rmd HTML report) and all `bcftools_stats_*`/`bcftools_concat`
  rules are no longer wanted. `multiqc` stays.

## Goal

Simplify the pipeline to a single-caller (HaplotypeCaller-only), leaner QC
surface: drop the VCF HTML report and all bcftools-stats rules while keeping
`multiqc`, `vcf_stats` (vcftools-based per-chrom stats — independent of
bcftools, not requested for removal), and everything else in the
HaplotypeCaller path (including the `hc_scatter` toggle from the prior
branch) untouched.

## Scope decisions (confirmed with user)

1. Orphaned files (`workflow/envs/gatk3.yaml` + its 2 pin files,
   `workflow/envs/r.yaml`, `workflow/scripts/report_vcf.Rmd`,
   `workflow/report/report_vcf.rst`) are deleted, not left in place.
2. `samtools_stats_HC` and `validatesam_HC` — currently defined via
   `use rule X as Y with:` inheriting from a base rule (`samtools_stats`,
   `validatesam`) that exists only to serve the UnifiedGenotyper path — are
   converted to standalone rules with their own full body, so the UG-only
   base rules can be deleted cleanly.
3. `CLAUDE.md` is updated to remove the dual-caller/indel-realignment
   narrative, so documentation matches the simplified pipeline.

## Out of scope (confirmed pre-existing, not touched)

- `workflow/rules/combinegvcfs.smk` — already dead code, not in the
  `Snakefile` `include:` list. Unrelated to this change.
- `workflow/rules/old/` — pre-existing legacy files, not included by
  `Snakefile`. Unrelated.
- `profile/config.yaml` and `profile/hard.yaml` (repo root, outside
  `profile/cluster/` and `profile/local/`) — confirmed stale duplicates of
  `profile/cluster/config.yaml`/`hard.yaml`, not referenced by `run_shave.sh`
  (which only uses `profile/cluster` and `profile/local`). Pre-existing,
  already out of sync (missing the `HaplotypeCaller_wholegenome` entry from
  the prior branch) — left alone, not part of this cleanup.
- `vcf_stats.smk` (vcftools-based per-chrom stats) — independent of
  bcftools, not requested for removal, stays exactly as-is.

## Design — Part A: remove `report_vcf` + `bcftools_stats`, keep `multiqc`

**Delete entirely:**
- `workflow/rules/bcftools_stats.smk` (4 rules: `bcftools_stats_raw`,
  `bcftools_stats_filtered`, `bcftools_concat`, `bcftools_stats_genome`)
- `workflow/rules/report_vcf.smk` (1 rule: `report_vcf`)
- `workflow/envs/bcftools-1.15.1.yaml` + its pin files (only referenced by
  `bcftools_stats.smk`)
- `workflow/envs/r.yaml`, `workflow/scripts/report_vcf.Rmd`,
  `workflow/report/report_vcf.rst` (only referenced by `report_vcf.smk`)

**Edit `workflow/Snakefile`:**
- Remove the two `include:` lines for `bcftools_stats.smk` and
  `report_vcf.smk`.
- Remove `_bcftools_raw`, `_reports`, `_bcftools_genome` (both branches),
  `_bcftools_filtered` — keep `_vcftools` (vcf_stats output, independent).
- `_vcf_qc` becomes simply `_vcftools` in both the `skip_filtering` and
  `not skip_filtering` branches.

**Edit `workflow/rules/multiqc.smk`** (kept, not deleted):
- Remove `_mqc_vcf_raw`, `_mqc_bcftools_per_chrom`, `_mqc_bcftools_genome`
  variable definitions.
- Remove the three corresponding lines from `rule multiqc`'s `input:` list.
  (This edit happens alongside Part B's removal of the UG/HC branch split in
  the same file — see below.)

**Edit `profile/cluster/config.yaml`:** remove the `report_vcf:` resource
block. Keep `vcf_stats:`. (No `bcftools_stats_*`/`bcftools_concat` entries
exist in any profile — confirmed via grep, nothing to remove there.)

## Design — Part B: remove UnifiedGenotyper, IndelRealigner, RealignerTargetCreator

**Delete entirely:**
- `workflow/rules/ug.smk` (`create_bam_list`, `unifiedgenotyper`, `bgzip`)
- `workflow/rules/rtc.smk` (`realignertargetcreator`)
- `workflow/rules/indlr.smk` (`indelrealigner`)
- `workflow/rules/fixmateinformation.smk` (`sort_by_queryname`,
  `picard_fixmate`, `sort_by_coordinate`)
- `workflow/rules/awkforigv.smk` (`create_bed_file_for_igv`)
- `workflow/rules/setnmtag.smk` (`SetNmMdAndUqTags`) — orphaned once
  `rtc.smk`/`indlr.smk` (its only consumers) are gone.
- `workflow/envs/gatk3.yaml` + its 2 pin files (only used by `ug.smk`,
  `rtc.smk`, `indlr.smk`)

**Edit `workflow/rules/qualimap.smk`:** delete `rule qualimap_ug` (consumes
`fixmateinformation.smk` output). Keep `qualimap_hc` untouched.

**Edit `workflow/rules/samtools_index.smk`:** delete the
`use rule samtools_index as SetNmMdAndUqTags_index with:` block. Keep the
base `samtools_index` rule (used by the HC path).

**Edit `workflow/rules/samtools_stats.smk`:** convert `samtools_stats_HC`
from `use rule samtools_stats as samtools_stats_HC with:` into a standalone
rule with its own full body (message, resources, input, output, params, log,
conda, shell — copying the base rule's shared fields plus its own
overrides). Delete the base `samtools_stats` rule and the
`if config["caller"] == "HaplotypeCaller":` wrapper (moot once it's the only
rule in the file).

**Edit `workflow/rules/validatesam.smk`:** same treatment — convert
`validatesam_HC` to a standalone rule, delete the base `validatesam` rule.

**Edit `workflow/rules/common.smk`:** `get_final_vcf()` — remove the
`if config["caller"] == "HaplotypeCaller": ... else: ...` branch, collapse
to always return the HaplotypeCaller-shaped path
(`f"calls/all.{wildcards.chrom}.vcf.gz"` when `skip_filtering`).

**Edit `workflow/rules/filter_vcf.smk`:** `get_raw_vcf()` — same collapse,
always return `f"calls/all.{wildcards.chrom}.vcf.gz"`.

**Edit `workflow/rules/multiqc.smk`:** remove the
`if config["caller"] == "UnifiedGenotyper": rule multiqc: ... else: rule
multiqc: ...` split — keep only the HaplotypeCaller-branch rule body,
unconditionally, combined with Part A's removal of the bcftools/report
input lines.

**Edit `workflow/Snakefile`:**
- Remove `caller = config["caller"]` (confirmed unused anywhere else).
- Collapse the `if config["caller"] == "HaplotypeCaller": rule all: ... elif
  config["caller"] == "UnifiedGenotyper": ... else: raise ValueError(...)`
  into a single unconditional `rule all:` using the current HaplotypeCaller
  branch's inputs.
- Remove the 6 `include:` lines for `ug.smk`, `rtc.smk`, `indlr.smk`,
  `fixmateinformation.smk`, `awkforigv.smk`, `setnmtag.smk`.
- Remove `create_bed_file_for_igv` and `create_bam_list` from the
  `localrules:` list.
- `config["caller"]` becomes fully unused in the codebase after this change
  — the `caller:` key in `config/config.yaml` is left in place (harmless,
  unused config key) since removing it is not part of the stated ask; only
  code branching on it is removed. **Decision left as: keep the config key,
  remove all code that reads it**, since the user asked to remove rules, not
  edit `config.yaml`'s caller selector itself.

**Edit `workflow/rules/create_directories.smk`:** remove
`logs/gatk3/indelrealigner logs/gatk3/realignertargetcreator
logs/gatk3/unifiedgenotyper` and `logs/bgzip` and `logs/setnm` from the
`mkdir -p logs/...` line; remove `qc/qualimap_ug` from the `mkdir -p qc/...`
line.

**Edit `profile/cluster/config.yaml`:** remove resource blocks for
`SetNmMdAndUqTags`, `SetNmMdAndUqTags_index`, `realignertargetcreator`,
`indelrealigner`, `sort_by_queryname`, `picard_fixmate`,
`sort_by_coordinate`, `validatesam` (base), `samtools_stats` (base),
`qualimap_ug`, `unifiedgenotyper`, `bgzip`. Keep `validatesam_HC`,
`samtools_stats_HC`, `qualimap_hc`, and everything HaplotypeCaller/GATK4/
filtering-related untouched. (`profile/local/config.yaml` has none of these
rule names — confirmed, no changes needed there.)

**`multiqc_HC` resource entry** in `profile/cluster/config.yaml` (line
124-128) does not correspond to any rule in the codebase (only `multiqc`
exists) — pre-existing stale/unused entry, unrelated to this cleanup, left
untouched.

## `CLAUDE.md` updates

- Line 97: remove the `UnifiedGenotyper` bullet from the "Key Commands /
  Pipeline Architecture" caller list — HaplotypeCaller becomes the only
  caller described.
- Line 108, 111: remove indel-realignment/UG mentions from the pipeline
  stages list.
- Line 128: remove "Caller selection (HaplotypeCaller vs UnifiedGenotyper)"
  from the config system description.
- Line 165: remove `gatk3` from the "Major environments" list.
- Line 176: remove `UnifiedGenotyper` from the chromosome-parallelization
  rule list.
- Lines 188-199: remove the "Variant Calling Modes" `UnifiedGenotyper
  workflow` subsection entirely (RealignerTargetCreator/IndelRealigner/
  UnifiedGenotyper bullets), keep the `HaplotypeCaller workflow` subsection,
  and drop the `caller:` config-toggle framing sentence in favor of stating
  HaplotypeCaller is the only supported caller.

## Testing

Same method as the prior `hc_scatter` branch: `--dry-run` verification, since
this is a Snakemake DAG-wiring change with no unit-test suite in this repo.

- Dry-run before any change (baseline) vs. after Part A: confirm
  `bcftools_stats_*`/`bcftools_concat`/`report_vcf` no longer appear in the
  job list, `multiqc` and `vcf_stats` still do, and total job count drops by
  exactly the removed rules' instance counts.
- Dry-run after Part B: confirm no rule named `unifiedgenotyper`,
  `realignertargetcreator`, `indelrealigner`, `sort_by_queryname`,
  `picard_fixmate`, `sort_by_coordinate`, `create_bed_file_for_igv`,
  `create_bam_list`, `SetNmMdAndUqTags`, `SetNmMdAndUqTags_index`,
  `qualimap_ug`, `samtools_stats` (bare), `validatesam` (bare), or `bgzip`
  appears; confirm `samtools_stats_HC`, `validatesam_HC`, `qualimap_hc`,
  `multiqc`, and the full HaplotypeCaller chain still resolve correctly
  end-to-end.
- Since `config["caller"]` is never set to anything but `"HaplotypeCaller"`
  in `config/config.yaml` today, there is no config permutation to test for
  a removed "UnifiedGenotyper" branch — the branch is simply gone from the
  code.
