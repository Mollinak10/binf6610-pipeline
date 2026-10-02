#!/usr/bin/env bash
# Stage 9: copy the deliverables into results/ and write manifest.json.
set -euo pipefail

stage_publish() {
    local ws="$HERE/lib/write_manifest.sh"
    [[ -f "$ws" ]] || die "publish: $ws not found — put the course's write_manifest.sh in lib/"
    mkdir -p "$RES"
    log "  publishing deliverables to $RES"
    cp "$OUTDIR/07_analyze/cohort.filtered.vcf.gz"     "$RES/"
    cp "$OUTDIR/07_analyze/cohort.filtered.vcf.gz.tbi" "$RES/"
    cp "$OUTDIR/08_qc_report/multiqc_report.html"      "$RES/"
    need_file "$RES/cohort.filtered.vcf.gz" "publish"
    log "  writing manifest.json"
    bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"
    need_file "$RES/manifest.json" "publish"
    log "  manifest: $RES/manifest.json"
}
