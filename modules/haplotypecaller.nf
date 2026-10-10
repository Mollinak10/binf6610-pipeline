// Stage 5 · quantify — per-sample GVCF in params.region. Plain paths: they go only to collect().
process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    def heap = Math.round(task.memory.toMega() * 0.8)
    """
    gatk --java-options "-Xmx${heap}m" HaplotypeCaller \\
        -R ${ref} -I ${bam} -O ${meta.id}.g.vcf.gz -L ${params.region} -ERC GVCF \\
        --native-pair-hmm-threads ${task.cpus} --tmp-dir .
    """
}
