#!/usr/bin/env bash
# run_sample.sh — ONE sample, stages 0–5. A Slurm array task calls this.
# Stages 6–9 need every sample at once, so this script refuses them.
#
# Usage:  run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last_stage]
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

source "$HERE/lib/common.sh"
source_stages "$HERE"

usage() {
    echo "usage: $0 <samplesheet.csv> <outdir> <sample_id> [last_stage]" >&2
    exit 2
}

main() {
    [[ $# -ge 3 && $# -le 4 ]] || usage
    local sample=$3 to=${4:-quantify} last s
    last=$(stage_index "$to")
    (( last >= 0 )) || die "unknown stage '$to'"
    if (( last > 5 )); then
        die "run_sample.sh runs stages 0-5 for one sample; '$to' is a cohort stage (6-9) that needs every sample — run it with run_pipeline.sh"
    fi
    [[ -n "$sample" ]] || die "sample_id is empty"

    set_sheet "$1"
    setup_outdir "$2"
    load_samplesheet "$sample"

    log "=== stage 0: validate ('$sample') ==="
    stage_validate
    if (( last == 0 )); then log "stopping after validate"; return 0; fi

    check_environment
    for ((s = 1; s <= last; s++)); do
        log "=== stage $s: ${STAGES[$s]} ('$sample') ==="
        "stage_${STAGES[$s]}"
    done
    log "done: '$sample' stages 0-$last finished; outputs in $OUTDIR"
}

main "$@"
