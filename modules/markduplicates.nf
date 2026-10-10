// Stage 4 · postprocess — mark duplicates, then index.
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.markdup.bam"), path("${meta.id}.markdup.bam.bai"), emit: bam
    path "${meta.id}.markdup.metrics.txt", emit: metrics

    script:
    def heap = Math.round(task.memory.toMega() * 0.8)
    """
    gatk --java-options "-Xmx${heap}m" MarkDuplicates \\
        -I ${bam} -O ${meta.id}.markdup.bam -M ${meta.id}.markdup.metrics.txt --TMP_DIR .
    samtools index ${meta.id}.markdup.bam
    """
}
