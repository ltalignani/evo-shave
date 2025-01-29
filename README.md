SHAVE: SHort-read Alignment pipeline for VEctors 
==================================================================================================================

![MacOS](https://badgen.net/badge/icon/Sequoia%20(15.0)%20%7C%20Sonoma%20(14.7)%20%7C%20Ventura%20(13.7)%20%7C%20Monterey%20(12.7.6)/E6055C?icon=apple&label&list=%7C&scale=0.9) ![GNU/Linux](https://badgen.net/badge/icon/Focal%20Fossa%20(20.04)%20%7C%20Jammy%20Jellyfish%20(22.04)/772953?icon=https://www.svgrepo.com/show/25424/ubuntu-logo.svg&label&list=%7C&scale=0.9) ![Open Source](https://badgen.net/badge/icon/Open%20Source/purple?icon=https://upload.wikimedia.org/wikipedia/commons/4/44/Corazón.svg&label&scale=0.9) ![GNU AGPL v3](https://badgen.net/badge/Licence/GNU%20AGPL%20v3/grey?scale=0.9) ![Github](https://badgen.net/badge/icon/Github/?icon=gitlab&label&scale=0.9) ![Bash](https://badgen.net/badge/icon/Bash%205.1.16/black?icon=terminal&label&scale=0.9) ![Python](https://badgen.net/badge/icon/Python%203.12/black?icon=https://upload.wikimedia.org/wikipedia/commons/0/0a/Python.svg&label&scale=0.9) ![Snakemake](https://badgen.net/badge/icon/Snakemake%20(8.20)%20%7C%20(8.9.0)/green?icon=https://upload.wikimedia.org/wikipedia/commons/d/d3/Python_icon_(black_and_white).svg&label&scale=0.9) ![Conda](https://badgen.net/badge/icon/Conda%20(23.11.0)%20%7C%20Mamba%20(1.5.5)/black?icon=codacy&label&scale=0.9)

\~ ABOUT \~
-----------

SHAVE is a bioinformatics pipeline designed for **alignment and variant calling of mosquitoe genomes** (*Aedes* and *Anopheles*) using Illumina® short-reads, based on GATK® Best Practices (excluding the BQSR and VQSR steps, as explained below) and the [MalariaGEN pipelines](https://github.com/malariagen/pipelines).
In brief, SHAVE reports quality reads, removes adapters, aligns reads to a reference genome, marks duplicates, corrects bam tags (NM, MD, UQ), validates BAM files according to SAM/BAM specifications, and reports statistics.
SHAVE utilizes **GATK4® HaplotypeCaller** to call variants and genotype likelihoods, but it can also use **GATK3® UnifiedGenotyper** instead. SHAVE was created to adhere to the parameters of the **MalariaGEN pipelines** (phases 2 and 3), enabling variant and genotype calling under the same conditions used in the *1000 Genomes Anopheles gambiae project*. When using GATK3® UnifiedGenotyper, SHAVE adds indel realignment step before UnifiedGenotyper to call variants and genotypes, as done by MalariaGEN.
This pipeline considers practical realities. It can be run on a **local machine** or on a **cluster under slurm workload manager** 


**Note about BQSR and VQSR :**

The **Base Quality Score Recalibration** step requires a *known variation* VCF file, referring to the Ensembl-Variation database or dbSNP database, which store areas of the genome that differ between individual genomes (“variants”). However, we do not have a prior list of known variants for our *Aedes* species, which is why we cannot perform BQSR.

The value of BQSR is also [increasingly being
questioned](https://bmcbioinformatics.biomedcentral.com/articles/10.1186/s12859-016-1279-z#Abs1)
as mappers and callers are typically updated. Using HaplotypeCaller instead of
UnifiedGenotyper greatly improves the handling of indels.

**Variant Quality Score recalibration** is arguably the most challenging part of the Best Practices to get right [according to Broad
Institute](https://gatk.broadinstitute.org/hc/en-us/articles/4413056319131-VariantRecalibrator).
In essence, it is a sophisticated filtering technique applied to the variant callset that uses machine learning to model the technical profile of variants in a training set and uses that to filter out probable artifacts from the callset.

The key point is that it uses known, highly validated variant resources (such as Omni, 1000 Genomes, and HapMap) to select a subset of variants within our callset that we are confident are true positives (the training set). Unfortunately, no highly validated variant resource is available for *Aedes* at this time, so we decided to apply hard-filtering and leave the choice of parameters to the user. SHAVE extracts some information from the raw VCF to help in choosing the right parameters.


### Features

**SHAVE pipeline:**

-   Control reads quality (**fastQC** and **multiQC html report**),

-   Trim adapters

-   Align reads (*sam files*),

-   Convert sam into bam format and sort by coordinates,

-   Mark duplicates to BAM files,

-   Correct MD, NM and UQ tags into BAM files,

-   Validate BAM file according to SAM/BAM specifications,

-   Creates an Indels interval list if UnifiedGenotyper have been selected,

-   Create a .bed file to view the realignments in a genome viewer (IGV),

-   Realign Indels,

-   Index realigned bam,

-   Stats on bam,

-   Variant calling on each sample (*vcf files*),

-   Genotyping,

-   VCF compression,

-   Variant filtering

 

### Version

*V2.2024.09.27*

### Directed Acyclic Graph

#### UnifiedGenotyper

<img src="./visuals/dag_UG.png" width="1200" height="500">  

#### HaplotypeCaller

<img src="./visuals/dag_HC.png" width="1200" height="400">  


\~ INSTALLATIONS \~
-------------------

### Conda _(dependencies)_ ###

SHAVE utilizes the powerful **Conda or mamba** environment manager.
Therefore, if and only if _(Conda is not already installed)_, please install **Conda | mamba** first!

 
**Download** and **install** the version of the [Latest Miniconda Installer](https://docs.conda.io/en/latest/miniconda.html#latest-miniconda-installer-links) (23.5.2+) that is compatible with your operating system  

e.g. for **Linux_x86_64-bit** or **Windows Subsystem for Linux (WSL)** systems:  
```shell
curl https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o ~/Miniconda3-latest-Linux-x86_64.sh && \
bash ~/Miniconda3-latest-Linux-x86_64.sh -b -p ~/miniconda3/ && \
rm -f ~/Miniconda3-latest-Linux-x86_64.sh && \
~/miniconda3/condabin/conda update conda --yes && \
~/miniconda3/condabin/conda init && \
exit
```

e.g. for **MacOSX_INTEL-chips_x86_64-bit** or **MacOSX_M1/M2/M3-chips_arm_64-bit (with Rosetta)** systems:  
```shell
curl https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -o ~/Miniconda3-latest-MacOSX-x86_64.sh && \
bash ~/Miniconda3-latest-MacOSX-x86_64.sh -b -p ~/miniconda3/ && \
rm -f ~/Miniconda3-latest-MacOSX-x86_64.sh && \
~/miniconda3/condabin/conda update conda --yes && \
~/miniconda3/condabin/conda init && \
exit
```

Create a specific conda environment for **Snakemake v.8**: 
```shell
conda create -c conda-forge -c bioconda -n snakemake snakemake
conda activate snakemake
```


### SHAVE ###

Clone *(HTTPS)* the [shave](https://github.com/ltalignani/shave.git) repository on
github:

```shell
git clone git@github.com:ltalignani/shave.git
cd ./shave/
```

Difference between **Download** and **Clone**:  
- To create a copy of a remote repository’s files on your computer, you can
either **Download** or **Clone** the repository  
- If you download it, you **cannot sync** the repository with the remote
repository on GitHub  
- Cloning a repository is the same as downloading, except it preserves the Git
connection with the remote repository  
- You can then modify the files locally and upload the changes to the remote
repository on GitHub  
- You can then **update** the files locally and download the changes from the
remote repository on GitHub

```shell
git pull --verbose
```

\~ USAGE \~
-----------

1.  Local machine: activate your conda environment for snakemake 

2.  Copy your **paired-end** reads in **_R{1|2}.fastq.gz** format files
    into: **raw/** directory.

3.  Cluster usage: Edit the slurm profile according to your slurm account and
    cluster settings (partition names, mail): edit `config.yaml` file in
    `./profiles/default/` directory. The [snakemake--executor-plugin](https://snakemake.github.io/snakemake-plugin-catalog/plugins/executor/slurm.html) must be installed on the cluster module.

    See: 

    [Dynamic Resources Allocation](https://snakemake.readthedocs.io/en/stable/snakefiles/rules.html#dynamic-resources)  
    [Slurm Profiles](https://snakemake.readthedocs.io/en/stable/executing/cli.html#profiles)  
  
    for more info.

    **Important**: The `Start_shave.sh` script assumes that a `snakemake` and `conda` modules are installed on your cluster. You need to edit lines 35 and 36 of this script to adjust the module names.

1.  Local machine / Cluster usage: edit `config.yaml` file in `config/` directory

2.  Execute the pipeline on a local machine, use the **bash command:** 

```shell
snakemake --cores 32 --software-deployment-method conda apptainer --use-conda --conda-frontend conda --prioritize create_directories --keep-going --rerun-incomplete --retries 5 --local-cores 8
```
    
Available options:  
- `--cores`: change this number according to your local machine specifications.    
- `--conda-frontend`: conda | mamba  
- `--retries`: the number of times a job must be automatically restarted. This parameter is used to manage dynamic resources and affects both the memory usage and runtime of a rule (local) or job (cluster). If a rule/job fails, Snakemake’s internal `attempt` variable is incremented by 1 (e.g., from 1 to 2). This allows, for example, the allocated memory to be doubled when the job restarts. 

Alternatively, you can execute the `Start_shave.sh` bash script to run the pipeline on a cluster:

```shell
sbatch Start_shave.sh
```

Your analyzes will start.

\~ MEMORY AND RUNTIME MANAGEMENT \~ 

On a local computer, if you want to control how the `--retries` option affects the memory allocation of a rule, you can adjust the get_mem_mb function for each concerned rule, located in the `workflow/rules/` directory: 

```shell
def get_mem_mb(wildcards, attempt):
    mem = attempt * 8000
    print(f"Attempt {attempt}: Allocating {mem} MB of memory")
    return mem
```

Change `8000` by an other value. 

On a cluster, a slurm profile, present in `profile/config.yaml` and working in conjunction with the slurm-executor-plugin package, has been created to control the partition where each job is running, the number of cpus as well as the memory and time allocated to each job. These last two parameters are controlled by the snakemake variable `attempt` : 

```shell
executor: "slurm"
default-resources:
  slurm_account: "invalbo"
  slurm_partition: "long"
  runtime: f"{2 + attempt}h"
  cpus_per_task: 1
  nodes: 1
  tasks: 1
  mem_mb: max((1.5 * input.size_mb) * attempt, 4000)
jobs: 100
restart-times: 5
latency-wait: 60
rerun-incomplete: True
use-envmodules: False
use-conda: True
conda-frontend: conda
printshellcmds: True
max-jobs-per-second: 1
max-status-checks-per-second: 1
local-cores: 1

# Rules configuration
set-resources:
  fastqc:
    slurm_partition: "fast"
    cpus_per_task: 8
    mem_mb: attempt * 4000
    runtime: attempt * 60
  trimmomatic:
    slurm_partition: "fast"
    cpus_per_task: 8
    mem_mb: attempt * 8000
    runtime: attempt * 180
  ...
```

Jobs often fail due to insufficient memory or time allocation. To address this, SHAVE is programmed to make up to five attempts for each job, incrementing the `attempt` variable by 1 with each restart. The memory and time values specified in the slurm profile are then multiplied by the `attempt` value to ensure the job completes.
If you need to edit this Slurm configuration file, it is strongly recommended to only modify the numerical values and not remove the `attempt` variable.

see: 

[Workflow profile instructions](https://snakemake.readthedocs.io/en/stable/executing/cli.html#profiles),
[The snakemake profile project](https://github.com/snakemake-profiles/doc),
[Dynamic resources allocation](https://snakemake.readthedocs.io/en/stable/snakefiles/rules.html#dynamic-resources),

for more info.

\~ QUALITY CONTROL \~ 
----------------------

Yours results are available in **qc/** directory, as follow:

| File                    | Object                                                                 |
| ----------------------- | ---------------------------------------------------------------------- |
| **fastqc**              | raw reads quality reports for each sample, in *html* and *zip* formats |
| **markdup_metrics.txt** | bam metrics created by Picard MarkDuplicates                           |
| **Multiqc_data**        | Multiqc data                                                           |
| **Multiqc_report.html** | results agregation report for all samples, in *html* format            |
| **samtools**            | bam file statistics reports, in *txt* format                           |
| **validatesamfile**     | bam file validation report, in *txt* format                            |


\~ RESULTS \~
-------------

Yours results are available in **results/** directory, as follow:  


### 01_Trimming

| File                                     | Object                                                                    |
| ---------------------------------------- | ------------------------------------------------------------------------- |
| **XXX_trimmomatic_R1                     | 2.fastq.gz**                                                              | paired reads, without adapters and quality trimmed, in *fastq.gz* format |
| **XXX_trimmomatic_unpaired_R2.fastq.gz** | unpaired reads without adapters and quality trimmed, in *fastq.gz* format |



### 02_Mapping

| File         | Object                      |
| ------------ | --------------------------- |
| *sorted.bam* | Binary Alignment File       |
| *sorted.bai* | Binary Alignment File index |


### 04_Polishing


| File                           | Object                                                                                             |
| ------------------------------ | -------------------------------------------------------------------------------------------------- |
| *_md.bam*                      | marked bam file                                                                                    |
| *_md.bai*                      | marked bam file index                                                                              |
| *_tagged.bam*                  | tagged bam file (NM, MD UQ tags correction)                                                        |
| *_tagged.bai*                  | tagged bam file index                                                                              |
| **realignertargetcreator.bed** | local alignment intervals in *bed* format. Use in i.e. IGV with *./resources/genomes/AalbF3.fasta* |
| *realigned.bam*                | realigned bam files (if caller = UnifiedGenotyper in config file)                                  |
| *_realigned_stats*             | realigned bam statistics (if caller = UnifiedGenotyper in config file)                             |



### 05_Variants

| File        | Object                                 |
| ----------- | -------------------------------------- |
| **.vcf**    | variant calls, in *vcf* format         |
| **vcf.idx** | variant calls indexes, in *idx* format |

### 10_graphs

| File          | Object                                                                                                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **dag**       | directed acyclic graph of jobs, in *pdf* and *png* formats                                                                                                                            |
| **rulegraph** | dependency graph of rules, in *pdf* and *png* formats *(less crowded than above DAG of jobs, but also show less information)*                                                         |
| **filegraph** | dependency graph of rules with their input and output files in the dot language, in *pdf* and *png* formats *(an intermediate solution between above DAG of jobs and the rule graph)* |

### 11_Reports

| File              | Object                                                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **.log**          | All *non-empty* **log** for each tool and each sample                                                                              |
| files_summary.txt | summary of all files created by the workflow, in *txt* format *(columns: filename, modification time, rule version, status, plan)* |

\~ CONFIGURATION \~
-------------------

See or edit default settings in **config.yaml** file in **./config/** directory

### Resources

Edit to match your hardware configuration  
- **tmpdir**: for tools that can *(i.e. picard)* specify where you want the temp
stuff *(default config: '\$TMPDIR')*



### Environments
SHAVE use **conda** to set up environments. The files needed to create these environments are in the workflow/envs/ directory.
These environments have been freezed to ensure that people using this workflow will get exactly the same environments down to the individual package builds,
which is in fact very similar to providing the environment encapsulated in a container image. 
A fin <pin> file have been generated for each conda environment. Snakemake will try to use the contents of that file to determine conda packages to deploy. 


### Aligner

SHAVE use **BWA** to perform the alignment to the reference genome. 



### Mark Duplicates program

SHAVE use **picard MarkDuplicates** to perform this step. Picard works perfectly with GATK's programs. Can remove duplicates if needed *(default config)*


### Trimmomatic

-   **adapters**: link to adapters lists

-   **seedMisMatches**: specifies the maximum mismatch count which will still
    allow a full match to be performed

-   **palindromeClipTreshold**: specifies how accurate the match between the two
    'adapter ligated' reads must be for PE palindrome read alignment

-   **simpleClipThreshold**: specifies how accurate the match between any
    adapter etc. sequence must be against a read

-   **LeadMinTrimQual**: Cut bases off the start of a read, if below a threshold
    quality

-   **TrailMinTrimQual**: Cut bases off the end of a read, if below a threshold
    quality

-   **windowSize**: Performs a sliding window trimming approach. It starts
    scanning at the 5‟ end and clips the read once the average quality within
    the window falls below a threshold

-   **avgMinQual**: Drop the read if the average quality is below the specified
    level

-   **minReadLength**: Drop the read if it is below a specified length

-   **phred**: Convert quality scores to Phred-33 if phred-33 is selected
    (default)

### Directories tree structure

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ shell
🖥️️ Start_shave.sh
📚 README.md
📚 LICENSE
📂 visuals/
 ├── 📈 dag.png
📂 config/
 ├── ⚙️ config.yaml
 ├── ⚙️ fastq-screen.conf
📂 resources/
 ├── 📂 adapters/
 │    ├── 🧬 NexteraPE-PE.fa
 │    ├── 🧬 Truseq2-PE.fa
 │    ├── 🧬 Truseq2-SE.fa
 │    ├── 🧬 Truseq3-PE-2.fa
 │    ├── 🧬 Truseq3-PE.fa
 │    └── 🧬 Truseq2-SE.fa
 ├── 📂 genomes/
 │    └─── 🧬 AalbF5.fasta
 ├── 📂 indexes/
 │    └── 📂 bwa/
 │         ├── 🗂️ AgamP4
 │         ├── 🗂️ Adapters
 ├── 📂 reads/  
 │    ├── 🛡️ .gitkeep
 │    ├── 📦 ERR3343471_R1.fastq.gz
 │    └── 📦 ERR3343471_R2.fastq.gz
📂 profile/
 │    ├── ⚙️ config.yaml
 │    └── 📦 status-sacct.sh 
📂 workflow/
 ├──🍜 Snakefile
 ├── 📂 envs/
 │    ├── 🍜 bcftools-1.15.1.yaml
 │    ├── 🍜 bwa-0.7.17.yaml
 │    ├── 🍜 fastq-screen-0.14.0.yam
 │    ├── 🍜 fastqc-0.11.9.yaml
 │    ├── 🍜 gatk3.yaml
 │    ├── 🍜 gatk3.osx64.pin.txt
 │    ├── 🍜 samtools.yaml
 │    ├── 🍜 samtools.osx64.pin.txt
 │    ├── 🍜 stats.yaml
 │    ├── 🍜 trimmomatic.yaml
 │    └── 🍜 trimmomatic.osx64.pin.txt
 ├── 📂 rules/
 │    └── 📜 awkforigv.smk
 │    └── 📜 bwamem.smk
 │    └── 📜 common.smk
 │    └── 📜 create_directories.smk
 │    └── 📜 fastqc.smk
 │    └── 📜 indlr.smk
 │    └── 📜 markduplicates.smk
 │    └── 📜 qualimap.smk
 │    └── 📜 rtc.smk
 │    └── 📜 samtools_index.smk
 │    └── 📜 samtools_stats.smk
 │    └── 📜 setnmtag.smk
 │    └── 📜 trim.smk
 │    └── 📜 validatesam.smk
 └── 📂 scripts/
      └── 📜 common.py
      └── 📜 plot-depths.py
      └── 📜 report_vcf.Rmd
      └── 📜 report.Rmd
   
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

\~ SUPPORT \~
-------------

1.  Read The Fabulous Manual!

2.  Create a new issue: Issues \> New issue \> Describe your issue

3.  Send an email to [loic.talignani\@umontpellier.fr](url)

\~ ROADMAP \~
-------------

-   Add a wiki!
-   Add a container environment with snakemake

\~ AUTHORS & ACKNOWLEDGMENTS \~
-------------------------------

-   Loïc TALIGNANI (Developer and Maintener)

\~ CONTRIBUTING \~
------------------

Open to contributions!  
Testing code, finding issues, asking for update, proposing new features...  
Use Git tools to share!

\~ PROJECT STATUS \~
--------------------

This project is **regularly updated** and **actively maintened**  
However, you can be volunteer to step in as **developer** or **maintainer**

For information about main git roles:  
- **Guests** are *not active contributors* in private projects, they can only
see, and leave comments and issues  
- **Reporters** are *read-only contributors*, they can't write to the
repository, but can on issues  
- **Developers** are *direct contributors*, they have access to everything to go
from idea to production  
*Unless something has been explicitly restricted*  
- **Maintainers** are *super-developers*, they are able to push to master,
deploy to production  
*This role is often held by maintainers and engineering managers*  
- **Owners** are essentially *group-admins*, they can give access to groups and
have destructive capabilities

\~ LICENSE \~
-------------

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)

\~ REFERENCES \~
----------------

**Sustainable data analysis with Snakemake**  
Felix Mölder, Kim Philipp Jablonski, Brice Letcher, Michael B. Hall, Christopher
H. Tomkins-Tinch, Vanessa Sochat, Jan Forster, Soohyun Lee, Sven O. Twardziok,
Alexander Kanitz, Andreas Wilm, Manuel Holtgrewe, Sven Rahmann, Sven Nahnsen,
Johannes Köster  
*F1000Research (2021)*  
**DOI**: <https://doi.org/10.12688/f1000research.29032.2>  
**Publication**: <https://f1000research.com/articles/10-33/v1>  
**Source code**: <https://github.com/snakemake/snakemake>  
**Documentation**: <https://snakemake.readthedocs.io/en/stable/index.html>

**Anaconda Software Distribution**  
Team  
*Computer software (2016)*  
**DOI**:  
**Publication**: <https://www.anaconda.com>  
**Source code**: <https://github.com/snakemake/snakemake> (conda)  
**Documentation**: <https://snakemake.readthedocs.io/en/stable/index.html>
(conda)  
**Source code**: <https://github.com/mamba-org/mamba> (mamba) **Documentation**:
<https://mamba.readthedocs.io/en/latest/index.html> (mamba)

**Tabix: fast retrieval of sequence features from generic TAB-delimited files**  
Heng Li  
*Bioinformatics, Volume 27, Issue 5 (2011)*  
**DOI**: <https://doi.org/10.1093/bioinformatics/btq671>  
**Publication**: <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3042176/>  
**Source code**: <https://github.com/samtools/samtools>  
**Documentation**: <http://samtools.sourceforge.net>

**GATK: A MapReduce framework for analyzing next-generation DNA sequencing
data** *Genome Research, Volume 20: 1297-1303 (2010)* **DOI**:
<https://doi.org/10.1101/gr.107524.110> **Publication**:
<https://genome.cshlp.org/content/20/9/1297> **Source
code**:<https://github.com/broadinstitute/gatk>
**Documentation**:<https://gatk.broadinstitute.org/hc/en-us>

**Picard-tools**: *Broad Institute, GitHub repository (2019)* **DOI**:
**Publication**: **Source
code**:https://github.com/broadinstitute/picard](https://github.com/broadinstitute/picard)
**Documentation**:<https://broadinstitute.github.io/picard/>

**The AWK Programming Language**  
Al Aho, Brian Kernighan and Peter Weinberger  
*Addison-Wesley (1988)*  
**ISBN**: <https://www.biblio.com/9780201079814>  
**Publication**:  
**Source code**: <https://github.com/onetrueawk/awk>  
**Documentation**: <https://www.gnu.org/software/gawk/manual/gawk.html>

**Twelve years of SAMtools and BCFtools**  
Petr Danecek, James K Bonfield, Jennifer Liddle, John Marshall, Valeriu Ohan,
Martin O Pollard, Andrew Whitwham, Thomas Keane, Shane A McCarthy, Robert M
Davies and Heng Li  
*GigaScience, Volume 10, Issue 2 (2021)*  
**DOI**: <https://doi.org/10.1093/gigascience/giab008>  
**Publication**:
<https://academic.oup.com/gigascience/article/10/2/giab008/6137722>  
**Source code**: <https://github.com/samtools/samtools>  
**Documentation**: <http://samtools.sourceforge.net>

**Fast and accurate short read alignment with Burrows-Wheeler Transform**  
Heng Li and Richard Durbin  
*Bioinformatics, Volume 25, Aricle 1754-60 (2009)*  
**DOI**: <https://doi.org/10.1093/bioinformatics/btp324>  
**Publication**:
[https://pubmed.ncbi.nlm.nih.gov/19451168\@](https://pubmed.ncbi.nlm.nih.gov/19451168)  
**Source code**: <https://github.com/lh3/bwa>  
**Documentation**: <http://bio-bwa.sourceforge.net>

**TRIMMOMATIC: A flexible read trimming tool for Illumina NGS data**  
Bolger, A. M., Lohse, M., & Usadel, B. \_(2014)  
**DOI**: <https://doi.org/10.1093/bioinformatics/btu170>  
**Publication**: [Bolger, A. M., Lohse, M., & Usadel, B. (2014). Trimmomatic: A
flexible trimmer for Illumina Sequence Data. Bioinformatics,
btu170](https://academic.oup.com/bioinformatics/article/30/15/2114/2390096)  
**Source code**: <https://github.com/usadellab/Trimmomatic>  
**Documentation**:

**MultiQC: summarize analysis results for multiple tools and samples in a single
report**  
Philip Ewels, Måns Magnusson, Sverker Lundin and Max Käller  
*Bioinformatics, Volume 32, Issue 19 (2016)*  
**DOI**: <https://doi.org/10.1093/bioinformatics/btw354>  
**Publication**:
<https://academic.oup.com/bioinformatics/article/32/19/3047/2196507>  
**Source code**: <https://github.com/ewels/MultiQC>  
**Documentation**: <https://multiqc.info>

**FastQC: A quality control tool for high throughput sequence data**  
Simon Andrews  
*Online (2010)*  
**DOI**: <https://doi.org/>  
**Publication**:  
**Source code**: <https://github.com/s-andrews/FastQC>  
**Documentation**: <https://www.bioinformatics.babraham.ac.uk/projects/fastqc>
