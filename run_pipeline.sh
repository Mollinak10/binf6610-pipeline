#!/usr/bin/env bash
# run_pipeline.sh — every sample, stages 0–9.
#
# Usage:  run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]
#         FROM_STAGE=merge run_pipeline.sh ...   start at a later stage
#                                                (the cohort job uses this for stages 6–9)
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

source "$HERE/lib/common.sh"
source_stages "$HERE"

usage() {
    echo "usage: $0 <samplesheet.csv> <outdir> [last_stage]" >&2
    echo "stages: ${STAGES[*]}   (set FROM_STAGE to start later)" >&2
    exit 2
}

main() {
    [[ $# -ge 2 && $# -le 3 ]] || usage
    local to=${3:-publish} from=${FROM_STAGE:-validate} first last s
    first=$(stage_index "$from"); last=$(stage_index "$to")
    (( last >= 0 ))  || die "unknown stage '$to' (choose from: ${STAGES[*]})"
    (( first >= 0 )) || die "unknown FROM_STAGE '$from' (choose from: ${STAGES[*]})"
    (( first <= last )) || die "FROM_STAGE '$from' comes after last stage '$to'"

    set_sheet "$1"
    setup_outdir "$2"
    load_samplesheet ""

    if (( first == 0 )); then
        log "=== stage 0: validate ==="
        stage_validate
        if (( last == 0 )); then log "stopping after validate"; return 0; fi
        first=1
    else
        report_errors "samplesheet"
        log "starting at stage $first (${STAGES[$first]}) for ${#IDS[@]} sample(s)"
    fi

    check_environment
    for ((s = first; s <= last; s++)); do
        log "=== stage $s: ${STAGES[$s]} ==="
        "stage_${STAGES[$s]}"
    done
    log "done: stages through $last finished; outputs in $OUTDIR"
}

main "$@"
