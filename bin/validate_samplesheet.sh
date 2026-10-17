#!/usr/bin/env bash
# validate_samplesheet.sh <samplesheet.csv> <reference.fa> [reference.dict]
# Stage 0. Each FASTQ is opened at the path the samplesheet gives: absolute, or
# relative to the samplesheet's folder. (Snakemake links nothing into a task folder.)
set -euo pipefail
SHEET=${1:?usage}; REF=${2:?usage}; DICT=${3:-${REF%.*}.dict}
DIR=$(dirname "$SHEET")
at() { [[ -z "$1" || "$1" == /* ]] && printf '%s' "$1" || printf '%s/%s' "$DIR" "$1"; }
log() { printf '[validate] %s\n' "$*" >&2; }
problems=0
while IFS=, read -r id lt r1 r2; do
    [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }
    r1=$(at "$r1"); r2=$(at "$r2")
    case "$lt" in
        paired) [[ -n "$r2" ]] || { log "$id: library_type is paired but r2_fastq is empty"; problems=$(( problems + 1 )); } ;;
        single) [[ -z "$r2" ]] || { log "$id: library_type is single but r2_fastq is set"; problems=$(( problems + 1 )); } ;;
        *)      log "$id: library_type must be paired or single, got '$lt'"; problems=$(( problems + 1 )) ;;
    esac
    [[ -s "$r1" ]] || { log "$id: R1 is missing or empty: $r1"; problems=$(( problems + 1 )); continue; }
    if ! gzip -t "$r1" 2>/dev/null; then
        log "$id: R1 is not a complete gzip file: $r1"; problems=$(( problems + 1 )); continue
    fi
    n1=$(gzip -dc "$r1" | wc -l)
    (( n1 > 0 && n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"; problems=$(( problems + 1 )); }
    if [[ "$lt" == paired && -n "$r2" ]]; then
        if [[ ! -s "$r2" ]] || ! gzip -t "$r2" 2>/dev/null; then
            log "$id: R2 is missing or not a complete gzip file: $r2"; problems=$(( problems + 1 )); continue
        fi
        n2=$(gzip -dc "$r2" | wc -l)
        (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"; problems=$(( problems + 1 )); }
    fi
    log "$id: $lt-end, $(( n1 / 4 )) reads in R1"
done < <(awk -F, -v OFS=, '
    NR == 1 { for (i = 1; i <= NF; i++) { gsub(/\r/, "", $i); col[$i] = i }; next }
    { gsub(/\r/, ""); print $col["sample_id"], $col["library_type"], $col["r1_fastq"], $col["r2_fastq"] }' "$SHEET")
dupes=$(awk -F, 'NR > 1 { print $1 }' "$SHEET" | sort | uniq -d)
[[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }
[[ -s "$REF" ]]       || { log "no reference: $REF";              problems=$(( problems + 1 )); }
[[ -s "${REF}.fai" ]] || { log "no reference index: ${REF}.fai";  problems=$(( problems + 1 )); }
[[ -s "${REF}.bwt" ]] || { log "no BWA index: ${REF}.bwt";        problems=$(( problems + 1 )); }
[[ -s "$DICT" ]]      || { log "no sequence dictionary: $DICT";   problems=$(( problems + 1 )); }
(( problems == 0 )) || { log "validation failed with ${problems} problem(s)"; exit 65; }
log "validation passed: $(awk 'NR > 1' "$SHEET" | wc -l | tr -d ' ') samples"
