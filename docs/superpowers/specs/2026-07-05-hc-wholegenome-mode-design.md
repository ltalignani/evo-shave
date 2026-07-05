# HaplotypeCaller whole-genome mode — design spec

Date: 2026-07-05

## Problem

`HaplotypeCaller` always scatters per `{sample}×{chrom}` (`workflow/rules/hc.smk`),
regardless of `chromosomes.vcf_output` (which only controls which *final* VCF
targets are requested downstream of `GenotypeGVCFs`, not HC's scatter granularity).

With `chromosomes.auto: true` and no `min_size`/`pattern` filter, the active
reference (`GCA_018104305.1_AalbF3_genomic.fna`) has 574 contigs, so HC launches
574 jobs per sample. Per `profile/cluster/config.yaml`, each scaffold job
completes in well under a minute of actual compute (P95 ≈ 0.6 min), so job
scheduling/JVM-startup overhead dominates total wall-clock time across
samples × 574 jobs.

## Goal

Add an opt-in mode where HaplotypeCaller runs once per sample across the whole
genome (no `-L` interval restriction), producing a single GVCF per sample
instead of one GVCF per sample per contig — trading away per-contig
parallelism for drastically reduced per-job overhead on references with many
small scaffolds.

## Design

### Config

`config/config.yaml`, under the existing `chromosomes:` section, add:

```yaml
chromosomes:
  ...
  hc_scatter: true # true = one HaplotypeCaller job per sample per chrom (default, best for few large chromosomes)
                    # false = one HaplotypeCaller job per sample across the whole genome (best for references with many small scaffolds)
```

Default `true` preserves current behavior exactly (no breaking change).

### `workflow/rules/hc.smk`

Split into two mutually-exclusive rule definitions, selected at parse time via
`if config["chromosomes"].get("hc_scatter", True): ... else: ...`:

- **Scatter mode (existing, unchanged):** rule `HaplotypeCaller`, wildcards
  `{sample}, {chrom}`, uses `-L {chrom}`, output
  `calls/{sample}.{chrom}.g.vcf.gz`.
- **Whole-genome mode (new):** rule `HaplotypeCaller_wholegenome`, wildcard
  `{sample}` only, no `-L`, output `calls/{sample}.g.vcf.gz`.

Only one of the two rules exists in the DAG for a given config, since the
`if`/`else` is evaluated once at workflow parse time.

### `workflow/rules/genomicsdb.smk`

`genomics_db_import` keeps running once per chromosome (its output DB is still
partitioned by chrom for the rest of the pipeline). Its `gvcfs` input function
becomes conditional on `hc_scatter`:

- Scatter mode: unchanged — `expand("calls/{sample}.{chrom}.g.vcf.gz", sample=samples.index, chrom=[wildcards.chrom])`.
- Whole-genome mode: `expand("calls/{sample}.g.vcf.gz", sample=samples.index)` —
  the same whole-genome GVCF is reused as input for every `{chrom}` DB import;
  `GenomicsDBImport`'s existing `--intervals {chrom}` already subsets to the
  requested contig via the GVCF's tabix index, so no further change is needed
  there.

### `workflow/Snakefile` (`rule all`)

The HC target list (currently lines ~114-122, unconditional
`expand("calls/{sample}.{chrom}.g.vcf.gz", sample=samples.index, chrom=chromosomes)`)
becomes conditional the same way:

- Scatter mode: unchanged.
- Whole-genome mode: `expand("calls/{sample}.g.vcf.gz", sample=samples.index)`.

### `profile/local/config.yaml` / `profile/cluster/config.yaml`

Add a new resource block for `HaplotypeCaller_wholegenome`, distinct from the
existing `HaplotypeCaller` block (which stays tuned for sub-minute
per-scaffold jobs). Whole-genome jobs process an entire genome's worth of
reads in one process, so runtime/memory must scale accordingly — sized
generously since it's a new, uncalibrated code path (e.g. cluster runtime on
the order of `attempt * 720` minutes, refined later from observed run times).

## Out of scope

- `workflow/rules/combinegvcfs.smk` — not included in `workflow/Snakefile`
  (dead code), not touched.
- `UnifiedGenotyper` path (`ug.smk`) — unaffected, uses a different caller
  entirely.
- No change to `chromosomes.vcf_output`, `chromosomes.auto`,
  `chromosomes.min_size`, or `chromosomes.pattern` semantics.

## Testing

- `--dry-run` with `hc_scatter: true` (default) confirms DAG is byte-identical
  to current behavior (same rule names, same target files).
- `--dry-run` with `hc_scatter: false` confirms: one `HaplotypeCaller_wholegenome`
  job per sample, `genomics_db_import` jobs per chrom each depending on all
  samples' whole-genome GVCFs, and rule `all` requesting
  `calls/{sample}.g.vcf.gz` instead of the per-chrom pattern.
