# Configuration

## Required files

### `config/samples.tsv`

One row per biological sample. The `sample` column must match the sample names
used in `config/units.tsv`.

| Column | Description |
|---|---|
| `sample` | Unique sample identifier (string, may contain letters, digits, hyphens, dots) |

Example:
```
sample
FCV003
MPLS001
109
```

### `config/units.tsv`

One row per sequencing unit (one sample may span multiple lanes / units).
BAMs from multiple units are merged automatically before downstream processing.

| Column | Description |
|---|---|
| `sample` | Sample identifier — must match `samples.tsv` |
| `unit` | Lane or unit identifier (e.g. `L1`, `L8`) |
| `platform` | Sequencing platform (e.g. `ILLUMINA`) |
| `fq1` | Path to R1 FASTQ file (gzip-compressed) |
| `fq2` | Path to R2 FASTQ file (gzip-compressed) |

Example:
```
sample  unit  platform   fq1                           fq2
FCV003  L1    ILLUMINA   raw/FCV003_L1_R1.fastq.gz     raw/FCV003_L1_R2.fastq.gz
MPLS001 L1    ILLUMINA   raw/MPLS001_L1_R1.fastq.gz    raw/MPLS001_L1_R2.fastq.gz
```

---

## Key parameters (`config/config.yaml`)

### Reference genome

```yaml
refs:
  ref_name: "AalbF5"
  reference: "resources/genomes/AalbF5.fasta"   # path to FASTA
  index: "resources/genomes/AalbF5.fasta.fai"   # samtools fai index
  dict: "resources/genomes/AalbF5.dict"          # Picard sequence dictionary
```

BWA indices must be pre-built in `resources/indexes/bwa/`.

### Variant caller

```yaml
caller: "HaplotypeCaller"   # or "UnifiedGenotyper"
```

- **HaplotypeCaller** (GATK4): per-sample GVCF → joint genotyping. Recommended for most use cases.
- **UnifiedGenotyper** (GATK3): multi-sample calling with indel realignment. Use to match MalariaGEN phase 2/3 parameters.

### Chromosome / scaffold selection

```yaml
chromosomes:
  auto: true       # read contigs from .fai at parse time (recommended)
  min_size: 0      # exclude scaffolds smaller than N bp (0 = keep all)
  pattern: ""      # regex filter on contig names, e.g. "^NC_" (empty = keep all)
  list:            # used when auto: false
    - "NC_085136.1"
  vcf_output: "both"   # "per_contig" | "merged" | "both"
```

### MarkDuplicates

```yaml
markdup:
  skip: false            # set to true for ddRAD-seq data
  remove-duplicates: false
```

Set `skip: true` when processing ddRAD-seq libraries: enzymatic digestion
produces reads sharing the same start coordinates, which Picard would
incorrectly flag as PCR duplicates.

### Hard filtering thresholds

```yaml
filtering:
  hard:
    snvs: "QD < 2.0 || MQ < 40.0 || FS > 60.0 || SOR > 3.0 || MQRankSum < -12.5 || ReadPosRankSum < -8.0"
    indels: "QD < 2.0 || FS > 200.0 || SOR > 10.0 || ReadPosRankSum < -20.0"
```

Variants failing any threshold are tagged `FILTER` in the output VCF.
Adjust thresholds based on your species and library characteristics.

### Trimmomatic

```yaml
trimmomatic:
  adapters:
    truseq2-pe: "resources/adapters/TruSeq2-PE.fa"
  settings: "LEADING:20 TRAILING:3 SLIDINGWINDOW:5:20 AVGQUAL:20 MINLEN:50"
  phred: "-phred33"
```

### Results archiving (optional)

```yaml
transfer:
  results_dir: "/path/to/archive"
  run_name: "evo-shave"
```

Used by `transfer_results.sh` to rsync outputs to a shared archive after the run.
