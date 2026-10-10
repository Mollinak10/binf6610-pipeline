// Stage 2 · trim — adapters and low-quality tails, branching on meta.single_end.
process FASTP {
    tag "${meta.id}"
    container params.containers.fastp

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.trim.fastq.gz'), emit: reads
    path "${meta.id}.fastp.json",              emit: json

    script:
    if (meta.single_end)
        """
        fastp -w ${task.cpus} -i ${reads} -o ${meta.id}_R1.trim.fastq.gz \\
              -j ${meta.id}.fastp.json -h ${meta.id}.fastp.html
        """
    else
        """
        fastp -w ${task.cpus} -i ${reads[0]} -I ${reads[1]} --detect_adapter_for_pe \\
              -o ${meta.id}_R1.trim.fastq.gz -O ${meta.id}_R2.trim.fastq.gz \\
              -j ${meta.id}.fastp.json -h ${meta.id}.fastp.html
        """
}
