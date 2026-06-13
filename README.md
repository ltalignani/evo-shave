# SHAVE — SHort-read Alignment pipeline for VEctors

![macOS](https://badgen.net/badge/icon/macOS/E6055C?icon=apple&label&scale=0.9)
![GNU/Linux](https://badgen.net/badge/icon/GNU%2FLinux/772953?icon=https://www.svgrepo.com/show/25424/ubuntu-logo.svg&label&scale=0.9)
![Snakemake](https://badgen.net/badge/icon/Snakemake%20%E2%89%A59.0.0%20%7C%20tested%209.4.0/green?icon=https://upload.wikimedia.org/wikipedia/commons/d/d3/Python_icon_(black_and_white).svg&label&scale=0.9)
![Conda](https://badgen.net/badge/icon/Conda%2024%2B/black?icon=codacy&label&scale=0.9)
![Python](https://badgen.net/badge/icon/Python%203.12/black?icon=https://upload.wikimedia.org/wikipedia/commons/0/0a/Python.svg&label&scale=0.9)
![GNU AGPL v3](https://badgen.net/badge/Licence/GNU%20AGPL%20v3/grey?scale=0.9)

---

## About

SHAVE is a production-grade Snakemake pipeline for **alignment and variant calling of mosquito genomes** (*Aedes*, *Anopheles*, and related species) from Illumina paired-end short reads. It follows GATK Best Practices and is designed to match [MalariaGEN pipeline](https://github.com/malariagen/pipelines) parameters (phases 2 and 3), making results directly comparable to the *1000 Genomes Anopheles gambiae* project.

SHAVE runs on a **local workstation** or on a **SLURM cluster**, with fully automatic resource scaling, BAM-first scheduling, and post-run efficiency analysis.

---

## Features

### Variant calling

- **GATK4 HaplotypeCaller** — per-sample GVCF → GenomicsDBImport → joint GenotypeGVCFs
- **GATK3 UnifiedGenotyper** — multi-sample calling with indel realignment, matching MalariaGEN phase 2/3 parameters
- **Hard filtering** (GATK VariantFiltration) — SNV and indel filters configured in `config.yaml`; no truth set required
- **VCF output modes** — per-chromosome, genome-wide merged, or both

### Sequencing library support

- **Whole-genome sequencing** (WGS) — standard MarkDuplicates and hard-filtering workflow
- **ddRAD-seq** — MarkDuplicates bypass (`markdup.skip: true`) and hard-filtering bypass (`filtering.skip: true`) to avoid systematic artifacts from enzymatic digestion
- **Multi-lane samples** — BAMs from multiple sequencing lanes are automatically merged per sample before downstream processing

### Reference genomes

- *Aedes albopictus* AalbF5
- *Aedes albopictus* AalbF3
- *Aedes aegypti* AaegL5
- *Anopheles gambiae* AgamP4
- *Phocoena phoecoena* mPhoPho1.1
- *Orcinus orca* mOrcOrc1.1
- Any custom FASTA (provide `.fasta`, `.fai`, `.dict` and pre-built BWA indices)
- **Chromosome auto-detection** — reads contigs directly from `.fai` at parse time; configurable size and name filters for fragmented assemblies

### Quality control

- FastQC on raw reads
- Samtools stats on deduplicated BAMs
- Qualimap coverage reports
- bcftools stats on raw and filtered VCFs (per-chromosome + genome-wide)
- VCFtools frequency and statistics
- MultiQC HTML report aggregating all QC metrics

### SLURM cluster

- Dynamic resource allocation scaling with `input.size_mb` and `attempt`
- **BAM-first scheduling** — a barrier rule prevents variant-calling jobs from flooding the queue before all BAMs are produced
- Rule-level priority (`bwa_mem: 85`, `trimmomatic: 80`, etc.)
- Up to 500 concurrent SLURM jobs; configurable per-rule partition, CPU, memory, and runtime
- Automatic results archiving (`transfer_results.sh`)
- Post-run SLURM efficiency analysis (`analyze_efficiency.py`)

### Why no BQSR or VQSR?

**BQSR** requires a validated set of known variants (dbSNP / Ensembl Variation). No such resource exists for *Aedes* species, making BQSR inapplicable. **VQSR** similarly requires curated truth sets (HapMap, 1000 Genomes) unavailable for non-model organisms. SHAVE applies [GATK hard filtering](https://gatk.broadinstitute.org/hc/en-us/articles/360035531112) instead, with thresholds configurable in `config.yaml`.

---

## Quick start

```bash
# SLURM cluster
sbatch run_shave.sh

# Local (Mac Apple Silicon or Linux)
bash run_shave.sh

# Dry-run only
DRY_RUN=true bash run_shave.sh
```

`run_shave.sh` detects the environment automatically (`$SLURM_JOB_ID`, `uname -m`) and configures Snakemake accordingly. Edit the header variables (`LOCAL_CORES_CAP`, `CREATE_ENVS`, `DRY_RUN`) to tune behaviour without touching the rest of the script.

---

## Prerequisites

- [Miniforge3](https://github.com/conda-forge/miniforge) or Miniconda (conda ≥ 24.7.1)
- Python ≥ 3.10 (for the `.env` virtual environment)
- graphviz — `brew install graphviz` (Mac) / `apt install graphviz` (Linux) — optional, for workflow graphs

**Mac Apple Silicon:** install Miniforge3 for `osx-arm64`. The pipeline sets `CONDA_SUBDIR=osx-64` automatically so that bioconda packages are resolved via Rosetta 2.

---

## Installation

```bash
git clone https://github.com/ltalignani/shave.git
cd shave/

# Create the Python virtual environment with pinned dependencies
python3 -m venv .env
.env/bin/pip install -r requirements.txt
```

`requirements.txt` installs Snakemake ≥ 9.22.0, the SLURM executor plugin, and the graphviz Python binding. The pipeline uses `.env/bin/snakemake` automatically when the `.env` directory is present.

Update the repository at any time:

```bash
git pull --verbose
```

---

## Usage

### 1. Prepare input files

Place paired-end reads in the `raw/` directory. Accepted filename formats:

```
{sample}_L{n}_R{1|2}.fastq.gz      # already correct
{sample}_R{1|2}.fastq.gz            # lane L1 inserted automatically
{sample}_{1|2}.fastq.gz             # read number and lane normalised
{sample}_R{1|2}.fq.gz               # extension normalised
```

`Start_shave.sh` renames files automatically to `{sample}_L{n}_R{1|2}.fastq.gz` before running.

### 2. Edit the sample tables

**`config/samples.tsv`** — one row per biological sample:

```
sample
FCV003
MPLS001
```

**`config/units.tsv`** — one row per sequencing unit (sample × lane):

```
sample    unit    platform    fq1                          fq2
FCV003    L1      ILLUMINA    raw/FCV003_L1_R1.fastq.gz    raw/FCV003_L1_R2.fastq.gz
MPLS001   L1      ILLUMINA    raw/MPLS001_L1_R1.fastq.gz   raw/MPLS001_L1_R2.fastq.gz
```

### 3. Configure the pipeline

Edit `config/config.yaml`. Key settings:

```yaml
# Reference genome
refs:
  reference: "resources/genomes/AalbF5.fasta"

# Variant caller: "HaplotypeCaller" or "UnifiedGenotyper"
caller: "HaplotypeCaller"

# ddRAD-seq: skip MarkDuplicates and hard filtering
markdup:
  skip: false   # true for ddRAD-seq

filtering:
  skip: false   # true for ddRAD-seq (WGS thresholds are biologically inappropriate)

# Chromosome / scaffold selection
chromosomes:
  auto: true          # read contigs from .fai
  min_size: 0         # filter scaffolds below N bp
  pattern: ""         # regex filter on contig names (e.g. "^NC_")
  vcf_output: "both"  # "per_contig" | "merged" | "both"
```

When `filtering.skip: true`, all GATK VariantFiltration rules are removed from the DAG. VCF stats, genome-wide concatenation, and MultiQC all remain active and operate on the raw VCFs (`calls/all.raw.vcf.gz`).

### 4. Run the pipeline

```bash
# SLURM cluster
sbatch run_shave.sh

# Local (Mac Apple Silicon or Linux) — auto-detects CPU count
bash run_shave.sh
```

`run_shave.sh` handles: FastQ renaming, directory creation, conda environment setup, optional dry-run, post-run graph generation, and results archiving prompt.

### Dry-run

Set `DRY_RUN=true` in the header of `run_shave.sh`, or pass it inline:

```bash
DRY_RUN=true bash run_shave.sh
```

Use it when running for the first time, after modifying rules, or after changing the sample list.

---

## SLURM resource management

Resources are defined in `profile/cluster/config.yaml` and scale automatically with file size and retry count:

```yaml
set-resources:
  HaplotypeCaller:
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: attempt * 30
  bwa_mem:
    mem_mb: max((1.5 * input.size_mb) * attempt, 8000)
    runtime: max((input.size_mb / 1024) * 36 * attempt, 30)
```

When a job fails, `attempt` increments (1→2→3…) up to 5 retries, proportionally increasing memory and runtime.

### BAM-first scheduling

A barrier rule (`all_bams_ready`) prevents HaplotypeCaller and UnifiedGenotyper jobs from being submitted before all deduplicated BAMs exist. This avoids flooding the SLURM `long` partition queue — and depleting FairShare — while `fast` partition BAM jobs are still running.

### Cluster module requirements

`run_shave.sh` loads modules at submission time. Edit the `cluster)` block to match your cluster:

```bash
module load snakemake/9.4.0
module load conda
```

---

## Post-run tools

### SLURM efficiency analysis

After the pipeline completes, analyse CPU and memory efficiency per rule and generate an optimised `profile/config_optimized.yaml`:

```bash
bash analyze_efficiency.sh Cluster_logs/evoshave-*.out
diff profile/config.yaml profile/config_optimized.yaml
```

Options: `--mem-margin 1.3`, `--time-margin 1.5`, `--n-outliers 5`.

### Live memory monitoring

Run alongside the pipeline to capture peak `MaxRSS` per rule (required because this cluster does not populate `MaxRSS` in `sacct`):

```bash
bash monitor_memory.sh --interval 60 --output memory_log.tsv
```

### Results archiving

Transfer outputs to a shared archive and reset the pipeline for reuse:

```bash
sbatch transfer_results.sh
```

Configure destination in `config/config.yaml`:

```yaml
transfer:
  results_dir: "/shared/projects/invalbo/results"
  run_name: "evo-shave"
```

---

## Outputs

### QC (`qc/`)

| Path | Content |
|---|---|
| `qc/fastqc/` | FastQC HTML and ZIP reports per sample |
| `qc/markdup/` | Picard MarkDuplicates metrics |
| `qc/samtools/` | samtools stats per BAM |
| `qc/qualimap_hc/` | Qualimap coverage reports |
| `qc/validatesam/` | Picard ValidateSamFile reports |
| `qc/vcf_stats/` | bcftools stats and VCFtools frequency files |
| `qc/multiqc.html` | Aggregated MultiQC report |

### Alignments

| Path | Content |
|---|---|
| `mapped/{sample}_{unit}_sorted.bam` | Per-unit sorted BAM |
| `merged/{sample}_merged.bam` | Multi-lane merged BAM |
| `dedup/{sample}_sorted_md.bam` | Deduplicated BAM (or passthrough for ddRAD-seq) |

### Variant calls (`calls/`)

| Path | Content |
|---|---|
| `calls/{sample}.{chrom}.g.vcf.gz` | Per-sample GVCF (HaplotypeCaller) |
| `calls/all.{chrom}.vcf.gz` | Joint genotyped VCF per chromosome |
| `calls/all.{chrom}.filtered.vcf.gz` | Hard-filtered VCF per chromosome (`filtering.skip: false`) |
| `calls/all.filtered.vcf.gz` | Genome-wide merged filtered VCF (`filtering.skip: false`) |
| `calls/all.raw.vcf.gz` | Genome-wide merged raw VCF (`filtering.skip: true`) |

### Workflow graphs (`graphs/`)

DAG, rule graph, and file graph in PDF and PNG formats, generated automatically after the pipeline run.

---

## Pipeline architecture

```
FastQC → Trimmomatic → BWA-MEM → merge_bams → MarkDuplicates
                                                      ↓
                                           [all_bams_ready barrier]
                                                      ↓
                           ┌──── HaplotypeCaller (per sample × chromosome)
                           │           ↓
                           │     GenomicsDBImport
                           │           ↓
                           │     GenotypeGVCFs ────────────────┐
                           │                                    ↓
                           └──── UnifiedGenotyper     VariantFiltration
                                                               ↓
                                              bcftools stats + VCFtools + MultiQC
```

---

## Configuration reference

### Trimmomatic parameters (`config/config.yaml`)

| Parameter | Description |
|---|---|
| `adapters` | Path to adapter sequences |
| `LEADING` | Minimum quality to keep a leading base |
| `TRAILING` | Minimum quality to keep a trailing base |
| `SLIDINGWINDOW` | Window size : minimum average quality |
| `AVGQUAL` | Minimum average read quality |
| `MINLEN` | Minimum read length after trimming |

### Hard filtering thresholds

Configured under `filtering.hard` in `config/config.yaml`. Separate thresholds for SNVs and indels. Applied by GATK VariantFiltration; variants failing any filter are tagged `FILTER` (not removed).

Set `filtering.skip: true` to bypass all filtering steps. All QC rules (bcftools stats, VCFtools, MultiQC) remain active and operate on the raw VCFs. Recommended for ddRAD-seq, where WGS-calibrated thresholds are biologically inappropriate.

---

## Support

- Open an [issue on GitHub](https://github.com/ltalignani/shave/issues)
- Email: [loic.talignani@ird.fr](mailto:loic.talignani@ird.fr)

---

## Version

**V5.2026.06.14** — see [CHANGELOG.md](CHANGELOG.md) for full history.

---

## License

[GNU AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html)

---

## Authors

Loïc Talignani — UMR MIVEGEC, IRD Montpellier

---

## References

**Sustainable data analysis with Snakemake** — Mölder *et al.*, *F1000Research* (2021)
DOI: [10.12688/f1000research.29032.2](https://doi.org/10.12688/f1000research.29032.2)

**Fast and accurate short read alignment with Burrows-Wheeler Transform** — Li & Durbin, *Bioinformatics* (2009)
DOI: [10.1093/bioinformatics/btp324](https://doi.org/10.1093/bioinformatics/btp324)

**TRIMMOMATIC: A flexible read trimming tool for Illumina NGS data** — Bolger *et al.*, *Bioinformatics* (2014)
DOI: [10.1093/bioinformatics/btu170](https://doi.org/10.1093/bioinformatics/btu170)

**A framework for variation discovery and genotyping using next-generation DNA sequencing data** — DePristo *et al.*, *Nature Genetics* (2011)
DOI: [10.1038/ng.806](https://doi.org/10.1038/ng.806)

**Twelve years of SAMtools and BCFtools** — Danecek *et al.*, *GigaScience* (2021)
DOI: [10.1093/gigascience/giab008](https://doi.org/10.1093/gigascience/giab008)

**MultiQC: summarize analysis results for multiple tools and samples in a single report** — Ewels *et al.*, *Bioinformatics* (2016)
DOI: [10.1093/bioinformatics/btw354](https://doi.org/10.1093/bioinformatics/btw354)

**FastQC: A quality control tool for high throughput sequence data** — Andrews (2010)
[github.com/s-andrews/FastQC](https://github.com/s-andrews/FastQC)
