#!/usr/bin/env bash
# Stage 2: adapter and quality trimming with fastp.
set -euo pipefail

stage_trim() {
    local d="$OUTDIR/02_trim" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]}
        log "  fastp: $id (${TYPES[$i]})"
        if [[ "${TYPES[$i]}" == paired ]]; then
            run "$LOGDIR/02_fastp.$id.log" fastp -w "$THREADS" \
                -i "${R1S[$i]}" -I "${R2S[$i]}" \
                -o "$d/$id.R1.trim.fastq.gz" -O "$d/$id.R2.trim.fastq.gz" \
                --detect_adapter_for_pe \
                -j "$d/$id.fastp.json" -h "$d/$id.fastp.html"
            need_file "$d/$id.R2.trim.fastq.gz" "trim $id"
        else
            run "$LOGDIR/02_fastp.$id.log" fastp -w "$THREADS" \
                -i "${R1S[$i]}" -o "$d/$id.R1.trim.fastq.gz" \
                -j "$d/$id.fastp.json" -h "$d/$id.fastp.html"
        fi
        need_file "$d/$id.R1.trim.fastq.gz" "trim $id"
    done
}
