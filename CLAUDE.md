# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SHAVE (SHort-read Alignment pipeline for VEctors) is a Snakemake-based bioinformatics pipeline for alignment and variant calling of mosquito genomes (Aedes and Anopheles) using Illumina short-reads. The pipeline follows GATK Best Practices (excluding BQSR and VQSR) and is designed to match MalariaGEN pipeline parameters.

## Key Commands

### Local Execution
```bash
# Activate snakemake conda environment first
conda activate snakemake

# Run pipeline locally
snakemake --cores 32 --software-deployment-method conda apptainer --use-conda --conda-frontend conda --prioritize create_directories --keep-going --rerun-incomplete --retries 5 --local-cores 8
```

### Cluster Execution (SLURM)
```bash
# Submit job to cluster
sbatch Start_shave.sh

# The script handles:
# - Renaming FastQ files
# - Creating directory structure
# - Unlocking working directory
# - Setting up conda environments
# - Running Snakemake with SLURM executor
```

### Workflow Management
```bash
# Dry run to preview execution
snakemake --executor slurm --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores 32 --use-conda --conda-frontend conda --prioritize create_directories --dry-run

# Unlock working directory if locked
snakemake --workflow-profile profile --directory ${workdir}/ --unlock

# List conda environments
snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores 32 --list-conda-envs

# Clean up conda environments
snakemake --workflow-profile profile --directory ${workdir}/ --keep-going --rerun-incomplete --cores 32 --conda-cleanup-envs

# Generate workflow graphs (requires graphviz)
snakemake --workflow-profile profile --dag | dot -Tpdf > graphs/dag.pdf
snakemake --workflow-profile profile --rulegraph | dot -Tpdf > graphs/rulegraph.pdf
```

### Update Repository
```bash
git pull --verbose
```

### Generate QC Summary Statistics
```bash
# Activate snakemake conda environment
conda activate snakemake

# Parse samtools and qualimap statistics into CSV
python parse_stats_data.py
```

This generates `samtools_qualimap_summary.csv` combining samtools stats and qualimap results for all samples. Edit lines 120-122 in the script to customize input/output paths:
- `samtools_directory`: Directory with samtools stats files (default: `qc/samtools/`)
- `qualimap_directory`: Directory with qualimap reports (default: `qc/qualimap_hc/`)
- `destination_csv`: Output CSV filename (default: `samtools_qualimap_summary.csv`)

## Pipeline Architecture

### Workflow Structure
The pipeline is modular with rules organized in `workflow/rules/*.smk` files, all included in the main `workflow/Snakefile`. The workflow supports two variant callers:

1. **HaplotypeCaller** (GATK4): Modern caller with better indel handling
2. **UnifiedGenotyper** (GATK3): Legacy caller matching MalariaGEN phase 2/3 parameters, includes indel realignment

### Pipeline Stages
1. **QC**: FastQC on raw reads
2. **Trimming**: Trimmomatic adapter removal and quality trimming
3. **Alignment**: BWA-MEM to reference genome
4. **Merging**: Combine BAMs from multiple lanes/units per sample (merge_bams.smk)
5. **Polishing**:
   - Mark duplicates (Picard MarkDuplicates)
   - Set NM, MD, UQ tags
   - Validate BAM files
   - Optional: Indel realignment (UnifiedGenotyper only)
6. **Variant Calling**:
   - HaplotypeCaller: Per-sample GVCF generation → GenomicsDBImport → GenotypeGVCFs
   - UnifiedGenotyper: Direct multi-sample calling
7. **QC Reports**: samtools stats, Qualimap, MultiQC

### Sample/Unit Organization
- **samples.tsv**: One row per sample (biological specimen)
- **units.tsv**: One row per sequencing unit (sample + lane combination)
  - Columns: sample, unit, platform, fq1, fq2
  - Example: Sample "2000-24" can have units "L1" and "L8" (two lanes)
  - BAMs from multiple units are merged in merge_bams.smk before downstream processing
- Multiple configuration sets are maintained (samples_1.tsv through samples_8.tsv, units_1.tsv through units_8.tsv) for different analysis batches
  - To switch between configurations, update the `samples:` and `units:` paths in config/config.yaml
  - Default: `config/samples.tsv` and `config/units.tsv`

### Configuration System
- **config/config.yaml**: Main configuration
  - Trimming parameters (Trimmomatic settings)
  - Reference genome paths (supports AalbF5, AgamP4, custom references)
  - Caller selection (HaplotypeCaller vs UnifiedGenotyper)
  - GATK parameters (ERC mode, output mode, GenomicsDBImport options)
  - Chromosome list for parallelization
  - Hard filtering thresholds for SNVs and indels
- **config/samples.tsv**: Sample metadata
- **config/units.tsv**: Sequencing unit metadata with read file paths
- **profile/config.yaml**: SLURM executor profile with per-rule resource settings

### Dynamic Resource Allocation
The pipeline uses Snakemake's `attempt` variable for automatic resource scaling on retries:

**Local execution** (in individual rule files):
```python
def get_mem_mb(wildcards, attempt):
    mem = attempt * 8000  # Memory doubles on each retry
    print(f"Attempt {attempt}: Allocating {mem} MB of memory")
    return mem

rule example:
    resources:
        mem_mb=lambda wildcards, attempt: get_mem_mb(wildcards, attempt)
```

**Cluster execution** (in profile/config.yaml):
```yaml
set-resources:
  markduplicates_bam:
    mem_mb: max((1.5 * input.size_mb) * attempt, 16000)
    runtime: max((input.size_mb / 1024) * 18 * attempt, 120)
```

When a job fails, `attempt` increments (1→2→3...) up to 5 retries, increasing resources each time.

### Conda Environment Management
- Environments defined in `workflow/envs/*.yaml`
- Pinned environments (`.pin.txt` files) ensure reproducible builds
- Platform-specific pins: `linux-64` for clusters, `osx-64` for macOS
- Major environments: gatk3, gatk4, samtools, bwa, trimmomatic, fastqc, bcftools, multiqc

### Common Helper Functions (workflow/rules/common.smk)
- `get_fastq(wildcards)`: Returns read file paths for a sample-unit
- `is_single_end(sample, unit)`: Checks if sequencing is single-end
- `get_read_group(wildcards)`: Generates BWA read group string
- `get_trimmed_reads(wildcards)`: Returns trimmed read paths
- `get_sample_bams(wildcards)`: Returns all BAM files for a sample
- `get_bam_list(wildcards)`: Returns BAM list for merging (handles single/multiple units)

### Chromosome-Level Parallelization
Variant calling rules (HaplotypeCaller, GenotypeGVCFs, UnifiedGenotyper) use chromosome wildcards to parallelize across genomic regions. Chromosomes are defined in config.yaml.

## Important Implementation Details

### BAM Processing Workflow
1. BWA-MEM produces per-unit sorted BAMs: `mapped/{sample}_{unit}_sorted.bam`
2. merge_bams.smk merges units into: `merged/{sample}_merged.bam`
   - If only one unit exists, file is copied (not merged)
   - Uses Picard MergeSamFiles with coordinate sorting
3. All downstream steps (MarkDuplicates, SetNmTags, variant calling) use merged BAMs

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

### Module System (Cluster Only)
The merge_bams.smk rule and Start_shave.sh script use `module load` commands specific to the cluster environment:
- `module load picard/2.23.5`
- `module load snakemake/8.9.0`
- `module load conda`
- `module load graphviz/2.40.1`

When editing these files, preserve module load statements for cluster compatibility.

### File Naming Conventions
- Input reads: `{sample}_{unit}_R{1|2}.fastq.gz` (e.g., `2000-24_L8_R1.fastq.gz`)
- Trimmed: `trimmed/{sample}_{unit}_trimmomatic_R{1|2}.fastq.gz`
- Mapped: `mapped/{sample}_{unit}_sorted.bam`
- Merged: `merged/{sample}_merged.bam`
- Deduplicated: `dedup/{sample}_sorted_md.bam`
- Variant calls (HC): `calls/{sample}.{chrom}.g.vcf.gz`
- Variant calls (UG): `calls/variants.{chrom}.vcf.gz`

### GATK Best Practices Deviations
- **No BQSR**: Requires known variants database (unavailable for Aedes/Anopheles)
- **No VQSR**: Requires validated truth sets (unavailable for target species)
- **Hard filtering instead**: Thresholds defined in config.yaml filtering section

### QC Statistics Parser
The `parse_stats_data.py` script consolidates QC metrics from samtools and qualimap into a single CSV file with the following columns:
- Sample metadata and read counts
- Mapping statistics (mapped/unmapped reads, MapQ 30 reads)
- Duplicate rates and quality metrics
- Insert size statistics (average, median, standard deviation)
- Coverage statistics (mean coverage, coverage at 1X, 5X, 10X, 15X)
- Mapping quality metrics

The script parses:
1. `qc/samtools/{sample}_sorted_md.txt` - General BAM statistics
2. `qc/samtools/{sample}_sorted_md.q30.txt` - MapQ 30 filtered statistics
3. `qc/qualimap_hc/{sample}_report/genome_results.txt` - Coverage and quality metrics

## Development Notes

### Adding New Rules
1. Create rule file in `workflow/rules/`
2. Add `include:` statement in `workflow/Snakefile`
3. Define conda environment in `workflow/envs/`
4. Add resource settings to `profile/config.yaml` if needed
5. Include dynamic resources using `attempt` variable for retry resilience

### Modifying Resource Allocations
- **Local**: Edit `get_mem_mb()` functions in individual rule files
- **Cluster**: Edit `set-resources` section in `profile/config.yaml`
- Always use `attempt` variable for dynamic scaling
- Memory formula: `max((1.5 * input.size_mb) * attempt, minimum_mb)`
- Runtime formula: `max((input.size_mb / 1024) * factor * attempt, minimum_minutes)`

### Testing Changes
1. Use `--dry-run` to preview execution plan
2. Test on small sample subset first
3. Monitor `logs/` directory for errors
4. Check `qc/multiqc.html` for quality metrics

### Cluster Configuration
Edit `Start_shave.sh` lines 35-36 to match your cluster's module names:
```bash
module load snakemake/8.9.0  # Adjust version
module load conda
```

Edit `profile/config.yaml` to match your SLURM account and partitions:
```yaml
default-resources:
  slurm_account: "your_account"
  slurm_partition: "your_partition"
```

## Reference Genomes

The pipeline supports multiple reference genomes configured in config.yaml:
- AalbF5 (Aedes albopictus)
- AgamP4 (Anopheles gambiae PEST)
- mPhoPho1.1 (current default - Phoebe phoebe mosquito)
- Custom references (provide .fasta, .fai, .dict files)

BWA indices must be pre-built in `resources/indexes/bwa/`.
