// Stage 3 · align — BWA-MEM into a sorted BAM. SM is the sample's id, which names its VCF column.
process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    """
    bwa mem -t ${task.cpus} -R '@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA' ${ref} ${reads} \\
        | samtools sort -@ ${task.cpus} -T sort.tmp -o ${meta.id}.sorted.bam -
    test -s ${meta.id}.sorted.bam
    """
}
