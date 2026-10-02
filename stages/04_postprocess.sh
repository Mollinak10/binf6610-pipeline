#!/usr/bin/env bash
# Stage 4: index, mark duplicates, index again.
set -euo pipefail

stage_postprocess() {
    local a="$OUTDIR/03_align" d="$OUTDIR/04_postprocess" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} logf="$LOGDIR/04_markdup.${IDS[$i]}.log"
        log "  index + MarkDuplicates: $id"
        run "$logf" samtools index -@ "$THREADS" "$a/$id.sorted.bam"
        run "$logf" gatk_ MarkDuplicates -I "$a/$id.sorted.bam" \
            -O "$d/$id.markdup.bam" -M "$d/$id.markdup.metrics.txt"
        need_file "$d/$id.markdup.bam" "postprocess $id"
        run "$logf" samtools index -@ "$THREADS" "$d/$id.markdup.bam"
        need_file "$d/$id.markdup.bam.bai" "postprocess $id"
    done
}
