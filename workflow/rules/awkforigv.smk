rule create_bed_file_for_igv:
    message:
        "Awk IGV intervals visualization for {wildcards.sample}"
    input:
        intervals="dedup/{sample}.intervals",
    params:
        cmd=r"""'BEGIN { OFS = "\t" } { if( $3 == "") { print $1, $2-1, $2 } else { print $1, $2-1, $3}}'""",
    output:
        "dedup/{sample}_realignertargetcreator.bed",
    log:
        "logs/awk/{sample}_intervals_for_IGV.log",
    shell:
        "awk -F '[:-]' {params.cmd} {input.intervals} 1> {output.bed} 2> {log}"
