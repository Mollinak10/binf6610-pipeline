#!/usr/bin/env bash
# Stage 1: FastQC on the raw reads.
set -euo pipefail

stage_qc_raw() {
    local d="$OUTDIR/01_qc_raw" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} r1=${R1S[$i]} r2=${R2S[$i]}
        log "  FastQC: $id"
        if [[ "${TYPES[$i]}" == paired ]]; then
            run "$LOGDIR/01_fastqc.$id.log" fastqc -q -t "$THREADS" -o "$d" "$r1" "$r2"
            need_file "$d/$(fq_stem "$r2")_fastqc.zip" "qc_raw $id"
        else
            run "$LOGDIR/01_fastqc.$id.log" fastqc -q -t "$THREADS" -o "$d" "$r1"
        fi
        need_file "$d/$(fq_stem "$r1")_fastqc.zip" "qc_raw $id"
    done
}
