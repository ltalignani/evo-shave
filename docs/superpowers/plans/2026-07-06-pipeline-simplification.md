# Pipeline Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the evo-shave Snakemake pipeline to HaplotypeCaller-only by removing the UnifiedGenotyper/GATK3/indel-realignment path, and drop the VCF HTML report (`report_vcf`) and all `bcftools_stats`/`bcftools_concat` rules, while keeping `multiqc` and `vcf_stats` untouched.

**Architecture:** Two independently-verifiable removal passes over the Snakemake rule graph. Part A (Task 1) deletes the bcftools-stats/report-vcf rule files and prunes their target-list variables from `Snakefile` and their input references from `multiqc.smk`, leaving the dual-caller (`HaplotypeCaller`/`UnifiedGenotyper`) structure otherwise intact. Part B (Task 2) deletes every UnifiedGenotyper/indel-realignment rule file, converts the two `use rule ... with:` inheritors (`samtools_stats_HC`, `validatesam_HC`) into standalone rules so their now-orphaned base rules can be deleted, and collapses every `if config["caller"] == ...` branch (in `Snakefile`, `common.smk`, `filter_vcf.smk`, `multiqc.smk`) down to the HaplotypeCaller-only body. Each task lands as one commit that keeps `snakemake --dry-run` fully resolvable — no task leaves the DAG in a broken intermediate state.

**Tech Stack:** Snakemake 9.x, GATK4, no unit-test framework — verification is via `snakemake --dry-run` in an isolated git worktree, same method as the prior `hc_scatter` branch.

## Global Constraints

- Every task must leave `snakemake --dry-run` fully resolvable (no missing-rule/missing-include errors) — this is a hard gate, not a nice-to-have, since Snakemake fails fast on a dangling `include:` of a deleted file.
- `multiqc` and `vcf_stats.smk` are kept and must keep working — do not delete or break either.
- `workflow/rules/combinegvcfs.smk`, `workflow/rules/old/`, `profile/config.yaml`, `profile/hard.yaml` (repo-root duplicates) are out of scope — do not touch.
- `config/config.yaml`'s `caller:` key is left in place (unused after this change, but not part of the removal ask) — only code that *reads* `config["caller"]` is removed.
- `profile/local/config.yaml` has no UnifiedGenotyper/indel-realignment/bcftools_stats/report_vcf resource entries — confirmed via grep; no changes needed there in either task.
- Only `HaplotypeCaller` is ever set as `config["caller"]` in this repo's `config/config.yaml` today — no dry-run permutation is needed to prove a "UnifiedGenotyper" branch is gone, since removing the code removes the possibility outright.

---

### Task 1: Remove `report_vcf` and all `bcftools_stats` rules (keep `multiqc`, keep `vcf_stats`)

**Files:**
- Delete: `workflow/rules/bcftools_stats.smk`
- Delete: `workflow/rules/report_vcf.smk`
- Delete: `workflow/envs/bcftools-1.15.1.yaml`, `workflow/envs/bcftools-1.15.1.linux-64.pin.txt`
- Delete: `workflow/envs/r.yaml`, `workflow/envs/r.linux-64.pin.txt`, `workflow/envs/r.osx-64.pin.txt`
- Delete: `workflow/scripts/report_vcf.Rmd`
- Delete: `workflow/report/report_vcf.rst`
- Modify: `workflow/Snakefile:51,53,66-104`
- Modify: `workflow/rules/multiqc.smk:9-25,35-37,60-62`
- Modify: `profile/cluster/config.yaml:199-203`

**Interfaces:**
- Consumes: nothing from other tasks (this task is independent of Task 2).
- Produces: `_vcf_qc` (in `Snakefile`) becomes just `_vcftools` in both `skip_filtering` branches — Task 2 does not touch `_vcf_qc` again, so this is the final form.

- [ ] **Step 1: Delete the two rule files**

```bash
git rm workflow/rules/bcftools_stats.smk workflow/rules/report_vcf.smk
```

- [ ] **Step 2: Delete the orphaned env/script/report files**

```bash
git rm workflow/envs/bcftools-1.15.1.yaml workflow/envs/bcftools-1.15.1.linux-64.pin.txt
git rm workflow/envs/r.yaml workflow/envs/r.linux-64.pin.txt workflow/envs/r.osx-64.pin.txt
git rm workflow/scripts/report_vcf.Rmd
git rm workflow/report/report_vcf.rst
```

- [ ] **Step 3: Edit `workflow/Snakefile` — remove the two `include:` lines**

Find:
```python
include: "rules/bcftools_stats.smk"
include: "rules/vcf_stats.smk"
include: "rules/report_vcf.smk"
```

Replace with:
```python
include: "rules/vcf_stats.smk"
```

- [ ] **Step 4: Edit `workflow/Snakefile` — collapse the VCF-QC target-list block**

Find this entire block:
```python
if config.get("enable_variant_calling", True):
    _bcftools_raw = expand(
        "qc/vcf_stats/{chrom}.raw.bcftools_stats.txt", chrom=chromosomes
    )
    _vcftools = expand("qc/vcf_stats/vcf_{chrom}.frq", chrom=chromosomes)
    _reports = expand("qc/vcf_stats/report_vcf_{chrom}.html", chrom=chromosomes)

    if skip_filtering:
        # Raw mode: filtered per-chrom VCFs are not produced; raw VCFs are already
        # requested by the enable_variant_calling block below.
        _vcf_per_chrom = []
        _vcf_merged = ["calls/all.raw.vcf.gz"]
        _bcftools_filtered = []
        _bcftools_genome = ["qc/vcf_stats/all.raw.bcftools_stats.txt"]
        # Genome-wide concat always runs in skip mode regardless of vcf_output_mode
        _vcf_outputs = _vcf_merged
        _vcf_qc = _bcftools_raw + _vcftools + _reports + _bcftools_genome
    else:
        _vcf_per_chrom = expand("calls/all.{chrom}.filtered.vcf.gz", chrom=chromosomes)
        _vcf_merged = ["calls/all.filtered.vcf.gz"]
        _bcftools_filtered = expand(
            "qc/vcf_stats/{chrom}.filtered.bcftools_stats.txt", chrom=chromosomes
        )
        _bcftools_genome = ["qc/vcf_stats/all.filtered.bcftools_stats.txt"]

        if vcf_output_mode == "per_contig":
            _vcf_outputs = _vcf_per_chrom
        elif vcf_output_mode == "merged":
            _vcf_outputs = _vcf_merged
        else:  # "both"
            _vcf_outputs = _vcf_per_chrom + _vcf_merged

        _vcf_qc = _bcftools_raw + _bcftools_filtered + _vcftools + _reports
        if vcf_output_mode != "per_contig":
            _vcf_qc += _bcftools_genome
else:
    _vcf_outputs = []
    _vcf_qc = []
```

Replace with:
```python
if config.get("enable_variant_calling", True):
    _vcftools = expand("qc/vcf_stats/vcf_{chrom}.frq", chrom=chromosomes)

    if skip_filtering:
        # Raw mode: filtered per-chrom VCFs are not produced; raw VCFs are already
        # requested by the enable_variant_calling block below.
        _vcf_per_chrom = []
        _vcf_merged = ["calls/all.raw.vcf.gz"]
        # Genome-wide concat always runs in skip mode regardless of vcf_output_mode
        _vcf_outputs = _vcf_merged
        _vcf_qc = _vcftools
    else:
        _vcf_per_chrom = expand("calls/all.{chrom}.filtered.vcf.gz", chrom=chromosomes)
        _vcf_merged = ["calls/all.filtered.vcf.gz"]

        if vcf_output_mode == "per_contig":
            _vcf_outputs = _vcf_per_chrom
        elif vcf_output_mode == "merged":
            _vcf_outputs = _vcf_merged
        else:  # "both"
            _vcf_outputs = _vcf_per_chrom + _vcf_merged

        _vcf_qc = _vcftools
else:
    _vcf_outputs = []
    _vcf_qc = []
```

- [ ] **Step 5: Edit `workflow/rules/multiqc.smk` — remove bcftools/report variables and input lines**

Find:
```python
sample_unit_pairs = list(units.index)
samples_list = samples.index.tolist()

_mqc_fastqc = [
    f"qc/fastqc/{s}_{u}_R{read}.html"
    for s, u in sample_unit_pairs
    for read in [1, 2]
]
_mqc_markdup = expand("qc/markdup/{sample}_sorted_md_metrics.txt", sample=samples_list)
_mqc_vcf_raw = expand("qc/vcf_stats/{chrom}.raw.bcftools_stats.txt", chrom=chromosomes)

_mqc_bcftools_per_chrom = (
    []
    if skip_filtering
    else expand("qc/vcf_stats/{chrom}.filtered.bcftools_stats.txt", chrom=chromosomes)
)
_mqc_bcftools_genome = (
    ["qc/vcf_stats/all.raw.bcftools_stats.txt"]
    if skip_filtering
    else (
        ["qc/vcf_stats/all.filtered.bcftools_stats.txt"]
        if vcf_output_mode != "per_contig"
        else []
    )
)

if config["caller"] == "UnifiedGenotyper":

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}.fixed.sorted.txt", sample=samples_list),
            expand("qc/qualimap_ug/{sample}_report/qualimapReport.html", sample=samples_list),
            _mqc_vcf_raw,
            *_mqc_bcftools_per_chrom,
            *_mqc_bcftools_genome,
        output:
```

Replace with (note: the `if config["caller"] == "UnifiedGenotyper":` branch and its `rule multiqc:` body are UNCHANGED in this task — only the four bcftools-related lines are removed from its `input:` list; Task 2 removes this whole branch later):
```python
sample_unit_pairs = list(units.index)
samples_list = samples.index.tolist()

_mqc_fastqc = [
    f"qc/fastqc/{s}_{u}_R{read}.html"
    for s, u in sample_unit_pairs
    for read in [1, 2]
]
_mqc_markdup = expand("qc/markdup/{sample}_sorted_md_metrics.txt", sample=samples_list)

if config["caller"] == "UnifiedGenotyper":

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}.fixed.sorted.txt", sample=samples_list),
            expand("qc/qualimap_ug/{sample}_report/qualimapReport.html", sample=samples_list),
        output:
```

Then find the second (HaplotypeCaller) rule body:
```python
else:  # HaplotypeCaller

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}_md.txt", sample=samples_list),
            expand("qc/qualimap_hc/{sample}_report/qualimapReport.html", sample=samples_list),
            _mqc_vcf_raw,
            *_mqc_bcftools_per_chrom,
            *_mqc_bcftools_genome,
        output:
```

Replace with:
```python
else:  # HaplotypeCaller

    rule multiqc:
        input:
            _mqc_fastqc,
            _mqc_markdup,
            expand("qc/samtools/{sample}_md.txt", sample=samples_list),
            expand("qc/qualimap_hc/{sample}_report/qualimapReport.html", sample=samples_list),
        output:
```

(Leave the `output:`/`params:`/`log:`/`wrapper:` blocks of both rule bodies exactly as they are — only the `input:` lists change.)

- [ ] **Step 6: Edit `profile/cluster/config.yaml` — remove the `report_vcf:` resource block**

Find:
```yaml
  report_vcf:
    slurm_partition: "fast"
    cpus_per_task: 1
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
    runtime: attempt * 60
  vcf_stats:
```

Replace with:
```yaml
  vcf_stats:
```

- [ ] **Step 7: Set up environment and verify with dry-run**

This repo has no fastq/genome data checked in — you need placeholder files for a dry-run to resolve past the input stage, exactly as was done for the prior `hc_scatter` branch. From your worktree root:

```bash
ln -s ../../.env .env
ln -s ../../resources resources
mkdir -p raw
tail -n +2 config/units.tsv | awk -F'\t' '{print $4; if ($5!="") print $5}' | sort -u | while read -r f; do touch "$f"; done
export PATH="$(dirname "$CONDA_EXE"):$PATH"
```

(This assumes your worktree is at `.worktrees/<branch-name>/` — adjust the `../../` relative paths if your worktree is nested differently. If `$CONDA_EXE` is unset, find the working conda with `which -a conda` and pick the one reporting version ≥ 24.7.)

Then run:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -40
```

Expected: dry-run completes with no errors. Confirm:
```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "bcftools_stats|bcftools_concat|report_vcf"
```
Expected: no output (these rules no longer exist in the DAG).

```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "^multiqc |^vcf_stats "
```
Expected: both `multiqc` (1 job) and `vcf_stats` (one job per chromosome) still appear.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Remove report_vcf and bcftools_stats rules, keep multiqc and vcf_stats

report_vcf (R/Rmd HTML report) and all bcftools_stats_*/bcftools_concat
rules are no longer wanted. multiqc and vcf_stats (vcftools-based,
independent of bcftools) are unaffected.
EOF
)"
```

---

### Task 2: Remove UnifiedGenotyper, IndelRealigner, RealignerTargetCreator and all rules that only served that path

**Files:**
- Delete: `workflow/rules/ug.smk`, `workflow/rules/rtc.smk`, `workflow/rules/indlr.smk`, `workflow/rules/fixmateinformation.smk`, `workflow/rules/awkforigv.smk`, `workflow/rules/setnmtag.smk`
- Delete: `workflow/envs/gatk3.yaml`, `workflow/envs/gatk3.linux-64.pin.txt`, `workflow/envs/gatk3.osx-64.pin.txt`
- Modify: `workflow/rules/qualimap.smk:1-30` (delete `qualimap_ug`, keep `qualimap_hc`)
- Modify: `workflow/rules/samtools_index.smk:22-30` (delete `SetNmMdAndUqTags_index`)
- Modify: `workflow/rules/samtools_stats.smk` (convert `samtools_stats_HC` to standalone, delete base `samtools_stats`)
- Modify: `workflow/rules/validatesam.smk` (convert `validatesam_HC` to standalone, delete base `validatesam`)
- Modify: `workflow/rules/common.smk:102-113` (`get_final_vcf` collapse)
- Modify: `workflow/rules/filter_vcf.smk:1-11` (`get_raw_vcf` collapse)
- Modify: `workflow/rules/multiqc.smk` (remove UG/HC branch split entirely — this is on top of Task 1's edit to this file)
- Modify: `workflow/Snakefile` (remove `caller` var, remove 6 includes, remove 2 `localrules:` entries, collapse `rule all`)
- Modify: `workflow/rules/create_directories.smk:9-11`
- Modify: `profile/cluster/config.yaml` (remove 12 resource blocks: `SetNmMdAndUqTags`, `SetNmMdAndUqTags_index`, `realignertargetcreator`, `indelrealigner`, `sort_by_queryname`, `picard_fixmate`, `sort_by_coordinate`, bare `validatesam`, bare `samtools_stats`, `qualimap_ug`, `unifiedgenotyper`, `bgzip`)

**Interfaces:**
- Consumes: Task 1's edited `workflow/rules/multiqc.smk` (the bcftools-free `input:` lists from Task 1, Step 5) and `workflow/Snakefile` (Task 1's `_vcf_qc`/`_vcftools` form) as the starting point — this task edits both files further.
- Produces: a single unconditional `rule multiqc:` (no caller branch), a single unconditional `rule all:` (no caller branch) — nothing downstream of this task references `config["caller"]` again.

- [ ] **Step 1: Delete the rule files and orphaned env files**

```bash
git rm workflow/rules/ug.smk workflow/rules/rtc.smk workflow/rules/indlr.smk workflow/rules/fixmateinformation.smk workflow/rules/awkforigv.smk workflow/rules/setnmtag.smk
git rm workflow/envs/gatk3.yaml workflow/envs/gatk3.linux-64.pin.txt workflow/envs/gatk3.osx-64.pin.txt
```

- [ ] **Step 2: Edit `workflow/rules/qualimap.smk` — delete `qualimap_ug`, keep `qualimap_hc`**

Replace the entire file content with:
```python
def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule qualimap_hc:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=get_mem_mb,
        runtime=720,
    input:
        bam=rules.markduplicates_bam.output.bam,
    output:
        directory("qc/qualimap_hc/{sample}_report"),
        report_html=report(
            "qc/qualimap_hc/{sample}_report/qualimapReport.html",
            caption="../report/qualimap_hc.rst",
            category="Alignment QC",
            subcategory="{sample}",
        ),
    conda:
        "../envs/qualimap.yaml"
    log:
        "logs/qualimap_hc/bamqc/{sample}_report.log",
    shell:
        """
        mkdir -p qc/qualimap_hc/{wildcards.sample}_report/
        qualimap bamqc -bam {input.bam} -c -nt {resources.cpus_per_task} --java-mem-size={resources.mem_mb}M -outdir qc/qualimap_hc/{wildcards.sample}_report &> {log}
        """
```

- [ ] **Step 3: Edit `workflow/rules/samtools_index.smk` — delete `SetNmMdAndUqTags_index`**

Replace the entire file content with:
```python
rule samtools_index:
    message:
        "Samtools index for {wildcards.sample} sample"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=4000,
        runtime=120,
    input:
        rules.markduplicates_bam.output.bam,
    output:
        "dedup/{sample}_sorted_md.bai",
    log:
        "logs/samtools_index/{sample}_sorted_md.log",
    params:
        extra="",  # optional params string
    threads: 4  # This value - 1 will be sent to -@
    wrapper:
        "v4.5.0/bio/samtools/index"
```

- [ ] **Step 4: Edit `workflow/rules/samtools_stats.smk` — convert `samtools_stats_HC` to standalone, delete base rule**

Replace the entire file content with:
```python
def get_mem_mb(wildcards, attempt):
    return attempt * 8000


rule samtools_stats_HC:
    message:
        "Samtools stats for {wildcards.sample} sample before HaplotypeCaller"
    resources:
        partition="fast",
        cpus_per_task=4,
        mem_mb=8000,
        runtime=120,
    input:
        bam="dedup/{sample}_sorted_md.bam",
    output:
        "qc/samtools/{sample}_md.txt",
    params:
        extra=lambda wildcards: f"-r {config['refs']['reference']}",  # Optional: extra arguments.
        region="",  # Optional: region string.
    log:
        "logs/samtools_stats/{sample}_tagged_stats.log",
    conda:
        "../envs/samtools.yaml"
    shell:
        """
        samtools stats -@ {resources.cpus_per_task} {params.extra} {input.bam} 1> {output} 2> {log}
        """
```

- [ ] **Step 5: Edit `workflow/rules/validatesam.smk` — convert `validatesam_HC` to standalone, delete base rule**

Replace the entire file content with:
```python
def get_mem_mb(wildcards, attempt):
    return attempt * 4000


reference_file = config["refs"]["reference"]


rule validatesam_HC:
    message:
        "picard ValidateSamFile for {wildcards.sample} sample before HaplotypeCaller"
    resources:
        partition="fast",
        cpus_per_task=1,
        mem_mb=get_mem_mb,
        runtime=60,
    input:
        bam="dedup/{sample}_sorted_md.bam",
        ref=reference_file,
    output:
        "qc/validatesam/{sample}_md.txt",
    params:
        extra="-M SUMMARY",
    conda:
        "../envs/picard-3.2.yaml"
    log:
        "logs/validatesam/{sample}_md_stats.log",
    shell:
        """
        picard ValidateSamFile -Xmx{resources.mem_mb}M -I {input.bam} -R {input.ref} -O {output} {params.extra} 2> {log} || true
        """
```

- [ ] **Step 6: Edit `workflow/rules/common.smk` — collapse `get_final_vcf`**

Find:
```python
def get_final_vcf(wildcards):
    """Return the final per-chromosome VCF for downstream QC rules.

    When filtering.skip is True (e.g. ddRAD-seq), points directly to the raw
    caller output. When False, points to the hard-filtered merged VCF.
    """
    if skip_filtering:
        if config["caller"] == "HaplotypeCaller":
            return f"calls/all.{wildcards.chrom}.vcf.gz"
        else:
            return f"calls/variants.{wildcards.chrom}.vcf.gz"
    return f"calls/all.{wildcards.chrom}.filtered.vcf.gz"
```

Replace with:
```python
def get_final_vcf(wildcards):
    """Return the final per-chromosome VCF for downstream QC rules.

    When filtering.skip is True (e.g. ddRAD-seq), points directly to the raw
    caller output. When False, points to the hard-filtered merged VCF.
    """
    if skip_filtering:
        return f"calls/all.{wildcards.chrom}.vcf.gz"
    return f"calls/all.{wildcards.chrom}.filtered.vcf.gz"
```

- [ ] **Step 7: Edit `workflow/rules/filter_vcf.smk` — collapse `get_raw_vcf`**

Find:
```python
    def get_raw_vcf(wildcards):
        """Return raw (pre-filter) per-chromosome VCF depending on caller."""
        if config["caller"] == "HaplotypeCaller":
            return f"calls/all.{wildcards.chrom}.vcf.gz"
        else:
            return f"calls/variants.{wildcards.chrom}.vcf.gz"
```

Replace with:
```python
    def get_raw_vcf(wildcards):
        """Return raw (pre-filter) per-chromosome VCF."""
        return f"calls/all.{wildcards.chrom}.vcf.gz"
```

- [ ] **Step 8: Edit `workflow/rules/multiqc.smk` — remove the caller branch, keep only the HaplotypeCaller body**

Replace the entire file content with:
```python
sample_unit_pairs = list(units.index)
samples_list = samples.index.tolist()

_mqc_fastqc = [
    f"qc/fastqc/{s}_{u}_R{read}.html"
    for s, u in sample_unit_pairs
    for read in [1, 2]
]
_mqc_markdup = expand("qc/markdup/{sample}_sorted_md_metrics.txt", sample=samples_list)

rule multiqc:
    input:
        _mqc_fastqc,
        _mqc_markdup,
        expand("qc/samtools/{sample}_md.txt", sample=samples_list),
        expand("qc/qualimap_hc/{sample}_report/qualimapReport.html", sample=samples_list),
    output:
        report(
            "qc/multiqc.html",
            caption="../report/multiqc.rst",
            category="Quality Control",
        ),
        directory("qc/multiqc_data"),
    params:
        extra="--verbose",
    log:
        "logs/multiqc.log",
    wrapper:
        "v4.6.0/bio/multiqc"
```

- [ ] **Step 9: Edit `workflow/Snakefile` — remove `caller` variable and the 6 now-dead includes**

Find:
```python
caller = config["caller"]


###############################################################################
# INCLUSION DES MODULES #
include: "rules/create_directories.smk"
include: "rules/common.smk"
include: "rules/bam_barrier.smk"
include: "rules/fastqc.smk"
include: "rules/trim.smk"
include: "rules/bwa.smk"
include: "rules/merge_bams.smk"
include: "rules/markduplicates.smk"
include: "rules/setnmtag.smk"
include: "rules/samtools_index.smk"
include: "rules/rtc.smk"
include: "rules/indlr.smk"
include: "rules/fixmateinformation.smk"
include: "rules/qualimap.smk"
include: "rules/awkforigv.smk"
include: "rules/samtools_stats.smk"
include: "rules/validatesam.smk"
include: "rules/multiqc.smk"
include: "rules/ug.smk"
include: "rules/hc.smk"
```

Replace with:
```python
###############################################################################
# INCLUSION DES MODULES #
include: "rules/create_directories.smk"
include: "rules/common.smk"
include: "rules/bam_barrier.smk"
include: "rules/fastqc.smk"
include: "rules/trim.smk"
include: "rules/bwa.smk"
include: "rules/merge_bams.smk"
include: "rules/markduplicates.smk"
include: "rules/samtools_index.smk"
include: "rules/qualimap.smk"
include: "rules/samtools_stats.smk"
include: "rules/validatesam.smk"
include: "rules/multiqc.smk"
include: "rules/hc.smk"
```

- [ ] **Step 10: Edit `workflow/Snakefile` — remove the 2 dead `localrules:` entries**

Find:
```python
localrules:
    create_directories,
    create_bed_file_for_igv,
    create_bam_list,
    all_bams_ready,
```

Replace with:
```python
localrules:
    create_directories,
    all_bams_ready,
```

- [ ] **Step 11: Edit `workflow/Snakefile` — collapse `rule all` to HaplotypeCaller-only**

Find:
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

elif config["caller"] == "UnifiedGenotyper":

    rule all:
        input:
            expand("qc/validatesam/{sample}.fixed.sorted.txt", sample=samples.index),
            expand("dedup/{sample}_realignertargetcreator.bed", sample=samples.index),
            "qc/multiqc.html",
            expand("merged/{sample}_merged.bam", sample=samples.index),
            (
                expand("calls/variants.{chrom}.vcf.gz", chrom=chromosomes)
                if config.get("enable_variant_calling", True)
                else []
            ),
            _vcf_outputs,
            _vcf_qc,

else:
    raise ValueError("Unsupported caller specified in config file.")
```

Replace with:
```python
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

- [ ] **Step 12: Edit `workflow/rules/create_directories.smk` — remove UG/indel-realignment/setnm dirs**

Find:
```python
        mkdir -p trimmed/ mapped/ dedup/ calls/ fixed/ graphs/ flags/ Cluster_logs/ tmp/
        mkdir -p logs/awk logs/bwa_mem logs/bgzip logs/gatk3/indelrealigner logs/gatk3/realignertargetcreator logs/gatk3/unifiedgenotyper logs/gatk4/genomicsdbimport logs/gatk4/haplotypecaller logs/gatk4/filter logs/fastqc logs/fastq-screen logs/samtools_index logs/samtools_stats logs/setnm logs/trimmomatic logs/md logs/qualimap/bamqc logs/validatesam logs/vcf_stats
        mkdir -p qc/fastqc qc/fastq-screen qc/markdup qc/qualimap_ug qc/qualimap_hc qc/multiqc_data qc/samtools qc/validatesam qc/vcf_stats
```

Replace with:
```python
        mkdir -p trimmed/ mapped/ dedup/ calls/ fixed/ graphs/ flags/ Cluster_logs/ tmp/
        mkdir -p logs/gatk4/genomicsdbimport logs/gatk4/haplotypecaller logs/gatk4/filter logs/fastqc logs/fastq-screen logs/samtools_index logs/samtools_stats logs/trimmomatic logs/md logs/qualimap/bamqc logs/validatesam logs/vcf_stats
        mkdir -p qc/fastqc qc/fastq-screen qc/markdup qc/qualimap_hc qc/multiqc_data qc/samtools qc/validatesam qc/vcf_stats
```

- [ ] **Step 13: Edit `profile/cluster/config.yaml` — remove the 11 UG/indel-realignment resource blocks**

Find this contiguous run (from `SetNmMdAndUqTags:` through `samtools_stats_HC:`, keeping `samtools_stats_HC:` and its contents):
```yaml
  SetNmMdAndUqTags:
    slurm_partition: "fast"
    cpus_per_task: 1
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
    runtime: max((input.size_mb / 1024) * 6 * attempt, 240)
  SetNmMdAndUqTags_index:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
    runtime: max((input.size_mb / 1024) * 6 * attempt, 120)
  realignertargetcreator:
    slurm_partition: "fast"
    cpus_per_task: 8
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: max((input.size_mb / 1024) * 12 * attempt, 240)
  indelrealigner:
    slurm_partition: "long"
    cpus_per_task: 1
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: max((input.size_mb / 1024) * 60 * attempt, 120)
  sort_by_queryname:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: max((input.size_mb / 1024) * 18 * attempt, 40)
  picard_fixmate:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 120
  sort_by_coordinate:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 180
  validatesam:
    slurm_partition: "fast"
    cpus_per_task: 1
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
    runtime: max((input.size_mb / 1024) * 18 * attempt, 60)
  validatesam_HC:
    slurm_partition: "fast"
    cpus_per_task: 2
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)  # reduced from 16000; calibrate with monitor_memory.sh
    runtime: max((input.size_mb / 1024) * 18 * attempt, 15)  # observed P95: 1.2 min × 1.5
  samtools_stats:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 120
  samtools_stats_HC:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 20  # observed P95: 1.9 min × 1.5
  qualimap_ug:
    slurm_partition: "fast"
    cpus_per_task: 8
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 720
  qualimap_hc:
```

Replace with:
```yaml
  validatesam_HC:
    slurm_partition: "fast"
    cpus_per_task: 2
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)  # reduced from 16000; calibrate with monitor_memory.sh
    runtime: max((input.size_mb / 1024) * 18 * attempt, 15)  # observed P95: 1.2 min × 1.5
  samtools_stats_HC:
    slurm_partition: "fast"
    cpus_per_task: 4
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 20  # observed P95: 1.9 min × 1.5
  qualimap_hc:
```

Then find (further down in the same file) the `unifiedgenotyper:`/`bgzip:` pair, immediately followed by `combine_gvcfs:`:
```yaml
  unifiedgenotyper:
    slurm_partition: "long"
    cpus_per_task: 8
    mem_mb: max((1.5 * input.size_mb) * attempt, 32000)
    runtime: attempt * 10080
  bgzip:
    slurm_partition: "fast"
    cpus_per_task: 8
    mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
    runtime: attempt * 120
  combine_gvcfs:
```

Replace with:
```yaml
  combine_gvcfs:
```

- [ ] **Step 14: Verify with dry-run**

From the same worktree set up in Task 1 Step 7 (re-export `PATH` if this is a new shell session):
```bash
export PATH="$(dirname "$CONDA_EXE"):$PATH"
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -40
```
Expected: dry-run completes with no errors.

```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "unifiedgenotyper|realignertargetcreator|indelrealigner|sort_by_queryname|picard_fixmate|sort_by_coordinate|create_bed_file_for_igv|create_bam_list|SetNmMdAndUqTags|qualimap_ug|^bgzip|^samtools_stats |^validatesam "
```
Expected: no output (bare `samtools_stats`/`validatesam`, without the `_HC` suffix, and all UG/indel-realignment rule names are gone from the DAG).

```bash
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | grep -E "^samtools_stats_HC |^validatesam_HC |^qualimap_hc |^multiqc |^HaplotypeCaller"
```
Expected: all four appear with non-zero job counts — confirms the standalone-converted rules and the full HaplotypeCaller chain still resolve.

- [ ] **Step 15: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Remove UnifiedGenotyper, IndelRealigner and RealignerTargetCreator

Collapses the pipeline to HaplotypeCaller-only. samtools_stats_HC and
validatesam_HC are converted from use-rule inheritance to standalone
rules since their UnifiedGenotyper-only base rules are removed.
qualimap_ug, the fixmate/sort chain, SetNmMdAndUqTags, and the GATK3
env are removed as no longer reachable.
EOF
)"
```

---

### Task 3: Update `CLAUDE.md`, add a CHANGELOG entry, final full verification

**Files:**
- Modify: `CLAUDE.md` (lines given below, from the version at the start of this task — re-read the file first since line numbers may have drifted from the version quoted here after Tasks 1-2 land on other files, though `CLAUDE.md` itself is untouched by Tasks 1-2)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing code-level from Tasks 1-2 — this is a documentation-only task plus a final combined dry-run check across both prior tasks' changes.

- [ ] **Step 1: Edit `CLAUDE.md` — remove the dual-caller narrative**

Find:
```
1. **HaplotypeCaller** (GATK4): Modern caller with better indel handling
2. **UnifiedGenotyper** (GATK3): Legacy caller matching MalariaGEN phase 2/3 parameters, includes indel realignment
```

Replace with:
```
HaplotypeCaller (GATK4) is the pipeline's variant caller.
```

Find:
```
5. **Polishing**:
   - Mark duplicates (Picard MarkDuplicates)
   - Set NM, MD, UQ tags
   - Validate BAM files
   - Optional: Indel realignment (UnifiedGenotyper only)
6. **Variant Calling**:
   - HaplotypeCaller: Per-sample GVCF generation → GenomicsDBImport → GenotypeGVCFs
   - UnifiedGenotyper: Direct multi-sample calling
```

Replace with:
```
5. **Polishing**:
   - Mark duplicates (Picard MarkDuplicates)
   - Validate BAM files
6. **Variant Calling**:
   - Per-sample GVCF generation → GenomicsDBImport → GenotypeGVCFs
```

Find:
```
- **config/config.yaml**: Main configuration
  - Trimming parameters (Trimmomatic settings)
  - Reference genome paths (supports AalbF5, AgamP4, custom references)
  - Caller selection (HaplotypeCaller vs UnifiedGenotyper)
  - GATK parameters (ERC mode, output mode, GenomicsDBImport options)
```

Replace with:
```
- **config/config.yaml**: Main configuration
  - Trimming parameters (Trimmomatic settings)
  - Reference genome paths (supports AalbF5, AgamP4, custom references)
  - GATK parameters (ERC mode, output mode, GenomicsDBImport options)
```

Find:
```
- Major environments: gatk3, gatk4, samtools, bwa, trimmomatic, fastqc, bcftools, multiqc
```

Replace with:
```
- Major environments: gatk4, samtools, bwa, trimmomatic, fastqc, multiqc
```

Find:
```
Variant calling rules (HaplotypeCaller, GenotypeGVCFs, UnifiedGenotyper) use chromosome wildcards to parallelize across genomic regions. Chromosomes are defined in config.yaml.
```

Replace with:
```
Variant calling rules (HaplotypeCaller, GenotypeGVCFs) use chromosome wildcards to parallelize across genomic regions. Chromosomes are defined in config.yaml.
```

Find this entire subsection:
```
### Variant Calling Modes
Set in config.yaml: `caller: "HaplotypeCaller"` or `caller: "UnifiedGenotyper"`

**HaplotypeCaller workflow:**
- Per-sample, per-chromosome GVCF generation
- GenomicsDBImport consolidates GVCFs
- GenotypeGVCFs performs joint genotyping
- No indel realignment step

**UnifiedGenotyper workflow:**
- RealignerTargetCreator creates indel intervals
- IndelRealigner performs local realignment
- UnifiedGenotyper performs multi-sample calling
- Creates .bed file for IGV visualization of realignments
```

Replace with:
```
### Variant Calling

**HaplotypeCaller workflow:**
- Per-sample, per-chromosome (or whole-genome, see `chromosomes.hc_scatter`) GVCF generation
- GenomicsDBImport consolidates GVCFs
- GenotypeGVCFs performs joint genotyping
```

- [ ] **Step 2: Add a CHANGELOG.md entry**

Read the top of `CHANGELOG.md` first to confirm the most recent entry's exact version number (it should be `V6.2026.07.05` per the prior `hc_scatter` branch, unless further entries have since been added — use the actual latest version number you find, incrementing the major version by one and using today's date).

Insert a new entry immediately after the `---` line that follows the file's header/format blurb (i.e. as the new first version entry), following the exact same structure as the existing entries (`## [Vx.YYYY.MM.DD] - date`, `### Added`/`### Removed` subsections, per-file `####` headers, prose explaining why):

```markdown
## [V7.2026.07.06] - 2026-07-06

### Removed

#### `workflow/rules/report_vcf.smk`, `workflow/rules/bcftools_stats.smk` — VCF report and bcftools stats

Removed the R/Rmd-based VCF HTML report (`report_vcf`) and all `bcftools_stats_*`/`bcftools_concat` rules. `multiqc` and `vcf_stats` (vcftools-based per-chrom stats) are unaffected and continue to run. Orphaned files removed alongside: `workflow/envs/bcftools-1.15.1.yaml` (+ pin), `workflow/envs/r.yaml` (+ pins), `workflow/scripts/report_vcf.Rmd`, `workflow/report/report_vcf.rst`.

#### `workflow/rules/ug.smk`, `workflow/rules/rtc.smk`, `workflow/rules/indlr.smk`, `workflow/rules/fixmateinformation.smk`, `workflow/rules/awkforigv.smk`, `workflow/rules/setnmtag.smk` — UnifiedGenotyper/GATK3/indel-realignment path

The legacy UnifiedGenotyper (GATK3) caller and its indel-realignment chain (RealignerTargetCreator, IndelRealigner, the fixmate/sort chain, SetNmMdAndUqTags, the IGV bed-file generator) are removed — HaplotypeCaller is now the pipeline's only caller. `samtools_stats_HC` and `validatesam_HC` were converted from `use rule ... with:` inheritance to standalone rules since their UnifiedGenotyper-only base rules (`samtools_stats`, `validatesam`) no longer exist. `qualimap_ug` is removed; `qualimap_hc` is unaffected. The orphaned `workflow/envs/gatk3.yaml` (+ pins) is removed. `workflow/Snakefile`'s `rule all` and `workflow/rules/multiqc.smk`'s `rule multiqc` are collapsed from a dual-caller branch to a single unconditional body. `config/config.yaml`'s `caller:` key is left in place (unused) but no code reads it any more.

---

```

- [ ] **Step 3: Final combined dry-run verification**

```bash
export PATH="$(dirname "$CONDA_EXE"):$PATH"
.env/bin/snakemake --workflow-profile profile/local --directory $(pwd)/ --dry-run 2>&1 | tail -40
```
Expected: dry-run completes with no errors.

```bash
python3 -c "import yaml; yaml.safe_load(open('profile/cluster/config.yaml')); print('OK')"
```
Expected: `OK` (confirms Task 2's YAML surgery didn't break parsing).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
Update CLAUDE.md and CHANGELOG for pipeline simplification

Removes the dual-caller/indel-realignment narrative from CLAUDE.md now
that UnifiedGenotyper is gone, and documents both removal passes in
CHANGELOG.md.
EOF
)"
```
