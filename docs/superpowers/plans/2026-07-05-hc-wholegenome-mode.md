# HaplotypeCaller Whole-Genome Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `chromosomes.hc_scatter: false` mode that runs HaplotypeCaller once per sample across the whole genome (no `-L` interval), instead of once per sample per chromosome — eliminating per-job scheduling/JVM-startup overhead on references with hundreds of small scaffolds.

**Architecture:** A single boolean config flag, resolved once in `workflow/rules/common.smk` as a module-level variable `hc_scatter` (same pattern as the existing `vcf_output_mode` / `skip_filtering` variables), gates three `if`/`else` branches evaluated at Snakemake parse time: which `HaplotypeCaller*` rule exists in `hc.smk`, what `genomics_db_import`'s input function returns in `genomicsdb.smk`, and what `rule all` requests in `Snakefile`. `GenomicsDBImport` itself is unchanged — it always runs once per chromosome and already subsets via `--intervals {chrom}`, which works against a whole-genome GVCF exactly as it does against a per-chrom one (tabix random access).

**Tech Stack:** Snakemake 9.x, GATK4, no test framework — verification is via `snakemake --dry-run` against both config states plus a full spec/config self-consistency check.

## Global Constraints

- Default (`hc_scatter` absent or `true`) must produce a byte-identical DAG to current behavior — no breaking change for existing configs.
- Only files identified in the spec are touched: `config/config.yaml`, `workflow/rules/common.smk`, `workflow/rules/hc.smk`, `workflow/rules/genomicsdb.smk`, `workflow/Snakefile`, `profile/local/config.yaml`, `profile/cluster/config.yaml`.
- `workflow/rules/combinegvcfs.smk` and `workflow/rules/ug.smk` are out of scope — do not modify.
- Whole-genome mode's new rule must be named `HaplotypeCaller_wholegenome` (distinct from the existing `HaplotypeCaller` rule) so cluster/local resource profiles can size it independently.
- Whole-genome output path: `calls/{sample}.g.vcf.gz` (no `{chrom}` in the filename).

---

### Task 1: Add `hc_scatter` config key and resolve it in `common.smk`

**Files:**
- Modify: `config/config.yaml` (chromosomes section, currently ends at the `vcf_output` line ~77)
- Modify: `workflow/rules/common.smk:87-93` (next to `vcf_output_mode` / `skip_filtering`)

**Interfaces:**
- Produces: module-level variable `hc_scatter` (bool), importable by any `.smk` file included after `common.smk` in `Snakefile` (same mechanism as `vcf_output_mode`, `skip_filtering`, `chromosomes`).

- [ ] **Step 1: Add the config key**

In `config/config.yaml`, find this block (inside `chromosomes:`):

```yaml
  vcf_output: "both" # "per_contig" | "merged" | "both"
```

Replace it with:

```yaml
  vcf_output: "both" # "per_contig" | "merged" | "both"
  hc_scatter: true # true = one HaplotypeCaller job per sample per chrom (default, best for few large chromosomes)
                    # false = one HaplotypeCaller job per sample across the whole genome (best for references with many small scaffolds, e.g. hundreds of contigs — avoids per-job scheduling/JVM overhead)
```

- [ ] **Step 2: Resolve the variable in `common.smk`**

In `workflow/rules/common.smk`, find:

```python
vcf_output_mode = (
    config["chromosomes"].get("vcf_output", "both")
    if isinstance(config["chromosomes"], dict)
    else "both"
)

skip_filtering = config.get("filtering", {}).get("skip", False)
```

Replace with:

```python
vcf_output_mode = (
    config["chromosomes"].get("vcf_output", "both")
    if isinstance(config["chromosomes"], dict)
    else "both"
)

hc_scatter = (
    config["chromosomes"].get("hc_scatter", True)
    if isinstance(config["chromosomes"], dict)
    else True
)

skip_filtering = config.get("filtering", {}).get("skip", False)
```

- [ ] **Step 3: Verify with a dry-run (default config unchanged)**

Run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -30
```
Expected: dry-run completes with no errors (identical job list to before this change — `hc_scatter` defaults to `true`).

- [ ] **Step 4: Commit**

```bash
git add config/config.yaml workflow/rules/common.smk
git commit -m "$(cat <<'EOF'
Add chromosomes.hc_scatter config toggle

Resolves the flag once in common.smk (same pattern as vcf_output_mode
and skip_filtering) so downstream rule files can branch on it without
repeating config.get() calls. Defaults to true, preserving current
per-chromosome HaplotypeCaller scatter behavior.
EOF
)"
```

---

### Task 2: Split `hc.smk` into scatter / whole-genome rule variants

**Files:**
- Modify: `workflow/rules/hc.smk` (entire file, currently lines 1-44)

**Interfaces:**
- Consumes: `hc_scatter` (bool, from Task 1's `common.smk`).
- Produces: when `hc_scatter=True`, rule `HaplotypeCaller` with outputs `calls/{sample}.{chrom}.g.vcf.gz` (unchanged from current). When `hc_scatter=False`, rule `HaplotypeCaller_wholegenome` with output `calls/{sample}.g.vcf.gz` — this exact rule name and output path are consumed by Task 3 and Task 4.

- [ ] **Step 1: Rewrite `workflow/rules/hc.smk`**

Replace the entire file content with:

```python
# PARAMETERS
reference_file = config["refs"]["reference"]
dictionary = config["refs"]["dict"]
index = config["refs"]["index"]

# FUNCTIONS AND COMMANDS
def get_mem_mb(wildcards, attempt):
    return attempt * 16000


if hc_scatter:

    rule HaplotypeCaller:
        message:
            "GATK's HaplotypeCaller SNPs and indels calling for {wildcards.sample} on {wildcards.chrom}"
        resources:
            partition="long",
            cpus_per_task=4,
            mem_mb=get_mem_mb,
            runtime=180,
        input:
            bam="dedup/{sample}_sorted_md.bam",
            index="dedup/{sample}_sorted_md.bai",
            barrier="flags/all_bams_ready.flag",
            reference=reference_file,
            dictionary=dictionary,
            fai=index,
        params:
            other_options=config["gatk"]["haplotypecaller"],  # -ERC GVCF
            output_mode=config["gatk"]["output_mode"],  # EMIT_ALL_CONFIDENT_SITES
            interval=lambda wildcards: f"-L {wildcards.chrom}" if wildcards.chrom else "",
        output:
            "calls/{sample}.{chrom}.g.vcf.gz",
        conda:
            "../envs/gatk4.yaml"
        log:
            "logs/gatk4/haplotypecaller/{sample}.{chrom}.log",
        shell:
            """
            gatk HaplotypeCaller --java-options "-Xmx{resources.mem_mb}M" \
            -R {input.reference} \
            -I {input.bam} \
            -O {output[0]} \
            {params.other_options} \
            --output-mode {params.output_mode} \
            {params.interval} &> {log}
            """

else:

    rule HaplotypeCaller_wholegenome:
        message:
            "GATK's HaplotypeCaller SNPs and indels calling for {wildcards.sample} across the whole genome"
        resources:
            partition="long",
            cpus_per_task=4,
            mem_mb=get_mem_mb,
            runtime=720,
        input:
            bam="dedup/{sample}_sorted_md.bam",
            index="dedup/{sample}_sorted_md.bai",
            barrier="flags/all_bams_ready.flag",
            reference=reference_file,
            dictionary=dictionary,
            fai=index,
        params:
            other_options=config["gatk"]["haplotypecaller"],  # -ERC GVCF
            output_mode=config["gatk"]["output_mode"],  # EMIT_ALL_CONFIDENT_SITES
        output:
            "calls/{sample}.g.vcf.gz",
        conda:
            "../envs/gatk4.yaml"
        log:
            "logs/gatk4/haplotypecaller/{sample}.wholegenome.log",
        shell:
            """
            gatk HaplotypeCaller --java-options "-Xmx{resources.mem_mb}M" \
            -R {input.reference} \
            -I {input.bam} \
            -O {output[0]} \
            {params.other_options} \
            --output-mode {params.output_mode} \
            &> {log}
            """
```

Note: `runtime=720` (12h) on the whole-genome rule is a deliberately generous starting point for an uncalibrated code path — local execution has no per-rule cluster queue time limit concerns, so this only matters for the cluster profile (tuned separately in Task 5).

- [ ] **Step 2: Verify default (scatter) dry-run still passes**

Run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "HaplotypeCaller|^Job stats"
```
Expected: shows rule `HaplotypeCaller` (not `HaplotypeCaller_wholegenome`) with one job per sample per chromosome, same count as before Task 1.

- [ ] **Step 3: Verify whole-genome dry-run**

Temporarily edit `config/config.yaml` to set `hc_scatter: false`, then run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "HaplotypeCaller|^Job stats"
```
Expected: shows rule `HaplotypeCaller_wholegenome` with exactly one job per sample (no `HaplotypeCaller` rule instantiated). This will likely error at this step because `genomics_db_import` (Task 3) and `rule all` (Task 4) still hard-reference `calls/{sample}.{chrom}.g.vcf.gz` — that's expected; the full whole-genome DAG will only resolve after Task 4. Confirm the error message is specifically a missing-input error referencing `calls/{sample}.g.vcf.gz` vs `calls/{sample}.{chrom}.g.vcf.gz`, not a Python/syntax error in `hc.smk` itself.

Revert `config/config.yaml` back to `hc_scatter: true` before continuing.

- [ ] **Step 4: Commit**

```bash
git add workflow/rules/hc.smk
git commit -m "$(cat <<'EOF'
Split HaplotypeCaller into scatter and whole-genome rule variants

Gated by the hc_scatter config flag from common.smk. Scatter mode
(default) is unchanged. Whole-genome mode adds a new
HaplotypeCaller_wholegenome rule producing one GVCF per sample across
the entire genome, with no -L interval restriction.
EOF
)"
```

---

### Task 3: Make `genomics_db_import`'s input conditional on `hc_scatter`

**Files:**
- Modify: `workflow/rules/genomicsdb.smk:11-16`

**Interfaces:**
- Consumes: `hc_scatter` (Task 1), `HaplotypeCaller_wholegenome` output path `calls/{sample}.g.vcf.gz` (Task 2).
- Produces: no change to `genomics_db_import`'s own output (`calls/db.{chrom}`) — only its `gvcfs` input list changes.

- [ ] **Step 1: Edit the input function**

In `workflow/rules/genomicsdb.smk`, find:

```python
    input:
        gvcfs=lambda wildcards: expand(
            "calls/{sample}.{chrom}.g.vcf.gz",
            sample=samples.index,
            chrom=[wildcards.chrom],
        ),
```

Replace with:

```python
    input:
        gvcfs=lambda wildcards: (
            expand(
                "calls/{sample}.{chrom}.g.vcf.gz",
                sample=samples.index,
                chrom=[wildcards.chrom],
            )
            if hc_scatter
            else expand("calls/{sample}.g.vcf.gz", sample=samples.index)
        ),
```

Note: in whole-genome mode, the same per-sample GVCF list is passed as input to every `genomics_db_import` job regardless of `{chrom}` — `--intervals {chrom}` (already set in `params.intervals` a few lines below, unchanged) does the actual per-chromosome subsetting via the GVCF's tabix index.

- [ ] **Step 2: Verify with dry-run (default scatter mode)**

Run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "genomics_db_import|^Job stats"
```
Expected: same job count and inputs as before this change (scatter mode unaffected).

- [ ] **Step 3: Commit**

```bash
git add workflow/rules/genomicsdb.smk
git commit -m "$(cat <<'EOF'
Make genomics_db_import input conditional on hc_scatter

In whole-genome mode, every per-chromosome GenomicsDBImport job reads
from the same whole-genome GVCF per sample; --intervals already
restricts the import to the requested contig via tabix random access.
EOF
)"
```

---

### Task 4: Make `rule all`'s HaplotypeCaller targets conditional on `hc_scatter`

**Files:**
- Modify: `workflow/Snakefile:106-124`

**Interfaces:**
- Consumes: `hc_scatter` (Task 1), `HaplotypeCaller_wholegenome` output path `calls/{sample}.g.vcf.gz` (Task 2).

- [ ] **Step 1: Edit the HaplotypeCaller `rule all` block**

In `workflow/Snakefile`, find:

```python
if config["caller"] == "HaplotypeCaller":

    rule all:
        input:
            "logs/.directories_created",
            expand("qc/validatesam/{sample}_md.txt", sample=samples.index),
            "qc/multiqc.html",
            expand("merged/{sample}_merged.bam", sample=samples.index),
            (
                expand(
                    "calls/{sample}.{chrom}.g.vcf.gz",
                    sample=samples.index,
                    chrom=chromosomes,
                )
                if config.get("enable_variant_calling", True)
                else []
            ),
            _vcf_outputs,
            _vcf_qc,
```

Replace with:

```python
if config["caller"] == "HaplotypeCaller":

    if hc_scatter:
        _hc_targets = expand(
            "calls/{sample}.{chrom}.g.vcf.gz",
            sample=samples.index,
            chrom=chromosomes,
        )
    else:
        _hc_targets = expand("calls/{sample}.g.vcf.gz", sample=samples.index)

    rule all:
        input:
            "logs/.directories_created",
            expand("qc/validatesam/{sample}_md.txt", sample=samples.index),
            "qc/multiqc.html",
            expand("merged/{sample}_merged.bam", sample=samples.index),
            _hc_targets if config.get("enable_variant_calling", True) else [],
            _vcf_outputs,
            _vcf_qc,
```

- [ ] **Step 2: Verify scatter mode dry-run (default, no regression)**

Run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -30
```
Expected: dry-run completes with no errors; job list identical to before Task 1 (same rule names, same target file counts).

- [ ] **Step 3: Verify whole-genome mode dry-run**

Temporarily set `hc_scatter: false` in `config/config.yaml`, then run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -40
```
Expected: dry-run completes with no errors. Confirm via:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -c "HaplotypeCaller_wholegenome"
```
Output should equal the number of samples in `config/samples.tsv` (one job per sample, not per sample×chrom). Also confirm no rule named plain `HaplotypeCaller` appears:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -w "HaplotypeCaller$"
```
Expected: no output (rule name would only match `HaplotypeCaller_wholegenome`, not bare `HaplotypeCaller`, due to the `-w` word-boundary flag... actually use this instead to be unambiguous:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "^rule HaplotypeCaller:"
```
Expected: no output.

Revert `config/config.yaml` back to `hc_scatter: true` before continuing.

- [ ] **Step 4: Commit**

```bash
git add workflow/Snakefile
git commit -m "$(cat <<'EOF'
Gate rule all's HaplotypeCaller targets on hc_scatter

Whole-genome mode requests one calls/{sample}.g.vcf.gz target per
sample instead of the per-chromosome expansion. This completes the
whole-genome DAG: HaplotypeCaller_wholegenome -> genomics_db_import ->
downstream unchanged.
EOF
)"
```

---

### Task 5: Add cluster/local resource profiles for `HaplotypeCaller_wholegenome`

**Files:**
- Modify: `profile/local/config.yaml:15-17` (next to the existing `HaplotypeCaller:` block)
- Modify: `profile/cluster/config.yaml:129-133` (next to the existing `HaplotypeCaller:` block)

**Interfaces:**
- Consumes: rule name `HaplotypeCaller_wholegenome` (Task 2) — must match exactly for Snakemake's `set-resources` to apply.

- [ ] **Step 1: Add local profile resources**

In `profile/local/config.yaml`, find:

```yaml
  HaplotypeCaller:
    cpus_per_task: 4
    mem_mb: 8000
  genomics_db_import:
```

Replace with:

```yaml
  HaplotypeCaller:
    cpus_per_task: 4
    mem_mb: 8000
  HaplotypeCaller_wholegenome:
    cpus_per_task: 4
    mem_mb: 16000
  genomics_db_import:
```

- [ ] **Step 2: Add cluster profile resources**

In `profile/cluster/config.yaml`, find:

```yaml
  HaplotypeCaller:
    slurm_partition: "long"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)  # reduced from 32000; calibrate with monitor_memory.sh
    runtime: attempt * 30  # observed P95: 0.6 min × 1.5; most scaffolds complete in < 1 min
  unifiedgenotyper:
```

Replace with:

```yaml
  HaplotypeCaller:
    slurm_partition: "long"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)  # reduced from 32000; calibrate with monitor_memory.sh
    runtime: attempt * 30  # observed P95: 0.6 min × 1.5; most scaffolds complete in < 1 min
  HaplotypeCaller_wholegenome:
    slurm_partition: "long"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 16000)  # uncalibrated: one job scans the whole genome per sample, not a single scaffold
    runtime: attempt * 720  # uncalibrated starting point (12h); refine once real run times are observed
  unifiedgenotyper:
```

- [ ] **Step 3: Verify YAML is well-formed**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('profile/local/config.yaml')); yaml.safe_load(open('profile/cluster/config.yaml')); print('OK')"
```
Expected: `OK`

- [ ] **Step 4: Verify cluster profile dry-run in whole-genome mode**

Temporarily set `hc_scatter: false` in `config/config.yaml`, then run:
```bash
.env/bin/snakemake --workflow-profile profile/cluster --executor local --directory $(pwd)/ --dry-run 2>&1 | tail -40
```
Expected: dry-run completes with no errors (confirms `set-resources` for `HaplotypeCaller_wholegenome` resolves without Snakemake complaining about referencing an unknown rule — Snakemake only errors on this if the rule name in the profile has a typo, since `set-resources` for a rule that isn't in the DAG on a given run is silently ignored, but it must still parse and, when the rule *is* in the DAG, apply cleanly).

Revert `config/config.yaml` back to `hc_scatter: true` before continuing.

- [ ] **Step 5: Commit**

```bash
git add profile/local/config.yaml profile/cluster/config.yaml
git commit -m "$(cat <<'EOF'
Add resource profiles for HaplotypeCaller_wholegenome

Sized independently from the existing per-scaffold HaplotypeCaller
entry (uncalibrated starting point: 16GB / 12h per sample, to be
refined from observed run times once whole-genome mode is used).
EOF
)"
```

---

### Task 6: Full end-to-end verification and spec/plan close-out

**Files:**
- None modified — verification only.

- [ ] **Step 1: Full dry-run, default config (hc_scatter true, unchanged)**

Run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -50
```
Expected: completes with no errors, job summary shows the same rules/counts as on `master` before this feature branch (spot-check: `HaplotypeCaller` job count == samples × chromosomes, no `HaplotypeCaller_wholegenome` in the plan).

- [ ] **Step 2: Full dry-run, whole-genome config**

Set `hc_scatter: false` in `config/config.yaml` (this time, leave it set for this verification), then run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -50
```
Expected: completes with no errors. Verify job counts:
```bash
SAMPLES=$(wc -l < config/samples.tsv)
echo "expected HaplotypeCaller_wholegenome jobs: $((SAMPLES - 1))"  # -1 for header row
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -c "^rule HaplotypeCaller_wholegenome:"
```
Expected: the grep count matches `$((SAMPLES - 1))`.

- [ ] **Step 3: Revert config to the safe default**

```bash
git diff config/config.yaml
```
Confirm the only diff remaining vs the last commit is none (i.e. `hc_scatter: true` was restored) — if `hc_scatter: false` is still set from Step 2, change it back to `true` now, since `true` is the intended shipped default:
```bash
git checkout -- config/config.yaml
```
(This restores the committed version from Task 1, which has `hc_scatter: true`.)

- [ ] **Step 4: Update CHANGELOG.md**

The file's most recent entry is `## [V5.2026.06.14] - 2026-06-14`, using `###` subsections (`### Added`) and per-file `####` headers with a short code block plus a prose paragraph explaining the "why". Follow that exact format.

In `CHANGELOG.md`, immediately after the `---` line that follows the header/format blurb (i.e. right before `## [V5.2026.06.14] - 2026-06-14`), insert:

```markdown
## [V6.2026.07.05] - 2026-07-05

### Added

#### `config/config.yaml` — `chromosomes.hc_scatter` toggle

```yaml
chromosomes:
  hc_scatter: true # true = one HaplotypeCaller job per sample per chrom (default, best for few large chromosomes)
                    # false = one HaplotypeCaller job per sample across the whole genome (best for references with many small scaffolds, e.g. hundreds of contigs — avoids per-job scheduling/JVM overhead)
```

References with hundreds of small scaffolds (e.g. `GCA_018104305.1_AalbF3_genomic.fna`, 574 contigs) previously forced HaplotypeCaller to launch 574 jobs per sample, each completing in well under a minute of actual compute — job scheduling and JVM-startup overhead dominated total wall-clock time. Setting `hc_scatter: false` runs HaplotypeCaller once per sample across the whole genome instead, trading away per-contig parallelism for drastically reduced overhead on such references.

#### `workflow/rules/common.smk` — `hc_scatter` flag

`hc_scatter = config["chromosomes"].get("hc_scatter", True)` is resolved once at parse time, following the same pattern as `vcf_output_mode` and `skip_filtering`.

#### `workflow/rules/hc.smk` — `HaplotypeCaller_wholegenome` rule

New rule active when `hc_scatter: false`, wildcarded only by `{sample}` (no `{chrom}`), with no `-L` interval restriction. Produces `calls/{sample}.g.vcf.gz` instead of one `calls/{sample}.{chrom}.g.vcf.gz` per chromosome.

#### `workflow/rules/genomicsdb.smk` and `workflow/Snakefile` — whole-genome wiring

`genomics_db_import`'s input and `rule all`'s HaplotypeCaller targets both branch on `hc_scatter`. In whole-genome mode, `GenomicsDBImport` still runs once per chromosome and imports from the same whole-genome GVCF per sample; its existing `--intervals {chrom}` subsets via the GVCF's tabix index exactly as before.

#### `profile/local/config.yaml` and `profile/cluster/config.yaml` — resource profile for the new rule

`HaplotypeCaller_wholegenome` gets its own resource entries, sized independently from the existing per-scaffold `HaplotypeCaller` entry (uncalibrated starting point: 16GB / 12h per sample on the cluster profile, to be refined from observed run times).

---

```

- [ ] **Step 5: Final commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
Document chromosomes.hc_scatter toggle in CHANGELOG
EOF
)"
```
