#!/usr/bin/env bash
# Stage 8: one MultiQC report across the cohort.
set -euo pipefail

stage_qc_report() {
    local d="$OUTDIR/08_qc_report"
    mkdir -p "$d"
    log "  MultiQC across the cohort"
    run "$LOGDIR/08_multiqc.log" multiqc -f -o "$d" "$OUTDIR/01_qc_raw" "$OUTDIR/02_trim" "$OUTDIR/04_postprocess"
    need_file "$d/multiqc_report.html" "qc_report"
}
