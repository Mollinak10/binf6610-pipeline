#!/usr/bin/env bash
# Stage 5: per-sample variant calling into a GVCF.
set -euo pipefail

stage_quantify() {
    local p="$OUTDIR/04_postprocess" d="$OUTDIR/05_quantify" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]}
        log "  HaplotypeCaller -ERC GVCF: $id"
        run "$LOGDIR/05_hc.$id.log" gatk_ HaplotypeCaller -R "$REF" \
            -I "$p/$id.markdup.bam" -O "$d/$id.g.vcf.gz" -L "$REGION" -ERC GVCF \
            --native-pair-hmm-threads "$THREADS"
        need_file "$d/$id.g.vcf.gz" "quantify $id"
    done
}
