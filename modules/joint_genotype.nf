// Stage 6 · merge — joint genotyping across every sample's GVCF, collected.
process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict

    output:
    tuple path('cohort.vcf.gz'), path('cohort.vcf.gz.tbi'), emit: vcf

    script:
    def heap = Math.round(task.memory.toMega() * 0.8)
    """
    args=""
    for g in ${gvcfs}; do args="\$args -V \$g"; done
    gatk --java-options "-Xmx${heap}m" CombineGVCFs -R ${ref} \$args \\
        -L ${params.region} -O cohort.g.vcf.gz --tmp-dir .
    gatk --java-options "-Xmx${heap}m" GenotypeGVCFs -R ${ref} -V cohort.g.vcf.gz \\
        -L ${params.region} -O cohort.vcf.gz --tmp-dir .
    """
}
