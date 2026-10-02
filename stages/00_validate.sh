#!/usr/bin/env bash
# Stage 0: check every loaded sample's input files before any compute,
# then report every problem together.
set -euo pipefail

stage_validate() {
    local i
    log "stage 0: validating $SHEET"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} type=${TYPES[$i]} r1=${R1S[$i]} r2=${R2S[$i]}
        local tag="sample '$id'" n1="" n2="" r1ok=0 r2ok=0
        if [[ ! -r "$r1" ]]; then add_error "$tag: R1 file not found: $r1"
        elif ! gzip -t "$r1" 2>/dev/null; then add_error "$tag: R1 is not a complete gzip file (truncated or corrupt): $r1"
        else r1ok=1
        fi
        if [[ "$type" == paired && -n "$r2" ]]; then
            if [[ ! -r "$r2" ]]; then add_error "$tag: R2 file not found: $r2"
            elif ! gzip -t "$r2" 2>/dev/null; then add_error "$tag: R2 is not a complete gzip file (truncated or corrupt): $r2"
            else r2ok=1
            fi
        fi
        if (( r1ok )); then
            if ! n1=$(gzip -dc "$r1" | wc -l); then n1=0; fi
            n1=${n1//[[:space:]]/}
            if (( n1 == 0 )); then add_error "$tag: R1 contains no reads"
            elif (( n1 % 4 != 0 )); then add_error "$tag: R1 has $n1 lines, not a multiple of 4"
            fi
        fi
        if (( r2ok )); then
            if ! n2=$(gzip -dc "$r2" | wc -l); then n2=0; fi
            n2=${n2//[[:space:]]/}
            if (( n2 % 4 != 0 )); then add_error "$tag: R2 has $n2 lines, not a multiple of 4"; fi
            if (( r1ok )) && [[ "$n1" != "$n2" ]]; then add_error "$tag: R1 has $((n1 / 4)) reads but R2 has $((n2 / 4))"; fi
        fi
        if (( r1ok )); then
            log "  checked '$id': $type-end, $((n1 / 4)) reads in R1${CONDS[$i]:+, condition=${CONDS[$i]}}"
        fi
    done
    report_errors "stage 0 failed"
    log "stage 0: OK — ${#IDS[@]} sample(s) validated"
}
