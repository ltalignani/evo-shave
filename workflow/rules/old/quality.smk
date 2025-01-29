rule fastqc:
    resources:
        partition="fast",
        cpus_per_task=8,
        mem_mb=16000,
        runtime=240,
    threads: 8
    input:
        "raw/{sample}_{unit}_{read}.fastq.gz",
    output:
        html="qc/fastqc/{sample}_{unit}_{read}.html",
        zip="qc/fastqc/{sample}_{unit}_{read}_fastqc.zip" # the suffix _fastqc.zip is necessary for multiqc to find the file. If not using multiqc, you are free to choose an arbitrary filename
    params:
        extra = "--quiet"
    log:
        "logs/fastqc/{sample}_{unit}_{read}.log"
    wrapper:
        "v4.4.0/bio/fastqc"


#fastq_screen_config = {
# 'database': {
#   'Phix': {
#     'bwa': 'resources/indexes/bwa/Phi-X174'},
#   'Adapters': {
#     'bwa': 'resources/indexes/bwa/Adapters'},
#   'Vectors': {
#     'bwa': 'resources/indexes/bwa/UniVec_wo_phi-X174'},
#   'Anopheles': {
#     'bwa': 'resources/indexes/bwa/Anopheles-gambiae-PEST_CHROMOSOMES_AgamP4'},
#   'Aedes': {
#     'bwa': 'resources/indexes/bwa/AalbF5_filtered'},
#  },
#  'aligner_paths': {'bwa': '/shared/ifbstor1/software/miniconda/envs/bwa-0.7.17/bin/bwa'}
#}


#rule fastq_screen:
#    resources:
#        partition="fast",
#        cpus_per_task=8,
#        mem_mb=16000,
#        runtime=240,
#    threads: 8
#    input:
#        "raw/{sample}_{unit}_{read}.fastq.gz"
#    output:
#        txt="qc/fastq-screen/{sample}_{unit}_{read}.fastq_screen.txt",
#        png="qc/fastq-screen/{sample}_{unit}_{read}.fastq_screen.png"
#    params:
#        fastq_screen_config="/shared/projects/invalbo/shave-slurm/config/fastq-screen.conf",
#        subset=100000,
#        aligner='bwa'
#    envmodules:
#        ["bwa/0.7.17"],
#    wrapper:
#        "v4.4.0/bio/fastq_screen"

