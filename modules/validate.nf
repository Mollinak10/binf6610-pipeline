// Stage 0 · validate — the samplesheet, every FASTQ and the reference, before any compute.
process VALIDATE {
    container params.containers.tools

    input:
    path samplesheet
    path fastqs
    path ref
    path ref_index
    path ref_dict

    output:
    path samplesheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${samplesheet} ${ref} ${ref_dict}
    """
}
