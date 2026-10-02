#!/usr/bin/env bash
# lib/common.sh — shared by run_pipeline.sh, run_sample.sh and every stage file:
# settings, logging, output folders, and reading the samplesheet by column name.
set -euo pipefail

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}
JAVA_MEM=${JAVA_MEM:-2g}
export TMPDIR=${TMPDIR:-/tmp}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

IDS=(); TYPES=(); R1S=(); R2S=(); CONDS=()
HEADER=()
ERRORS=(); NERR=0

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
add_error() { ERRORS+=("$1"); NERR=$((NERR + 1)); }

report_errors() {
    local i
    if (( NERR > 0 )); then
        for i in "${!ERRORS[@]}"; do log "  PROBLEM: ${ERRORS[$i]}"; done
        die "$1: $NERR problem(s) found — fix all of them and rerun"
    fi
}

trim() {
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

col_index() {
    local name=$1 i
    for i in "${!HEADER[@]}"; do
        if [[ "${HEADER[$i]}" == "$name" ]]; then echo "$i"; return 0; fi
    done
    echo -1
}

stage_index() {
    local name=$1 i
    for i in "${!STAGES[@]}"; do
        if [[ "${STAGES[$i]}" == "$name" ]]; then echo "$i"; return 0; fi
    done
    echo -1
}

resolve_path() {
    local p=$1
    if [[ -z "$p" ]]; then echo ""
    elif [[ "$p" == /* ]]; then echo "$p"
    elif [[ -e "$p" ]]; then echo "$PWD/$p"
    else echo "$SHEET_DIR/$p"
    fi
}

need_file() { [[ -s "$1" ]] || die "$2: expected output is missing or empty: $1"; }

run() {
    local logf=$1; shift
    if ! "$@" >>"$logf" 2>&1; then
        tail -n 20 "$logf" >&2
        die "command failed: $1 (full log: $logf)"
    fi
}

gatk_() { gatk --java-options "-Xmx${JAVA_MEM} -Djava.io.tmpdir=${TMPDIR}" "$@"; }

fq_stem() {
    local b; b=$(basename "$1")
    b=${b%.gz}; b=${b%.fastq}; b=${b%.fq}
    printf '%s' "$b"
}

set_sheet() {
    SHEET=$1
    [[ -f "$SHEET" ]] || die "samplesheet not found: $SHEET"
    SHEET_DIR=$(cd "$(dirname "$SHEET")" && pwd)
    SHEET="$SHEET_DIR/$(basename "$SHEET")"
}

setup_outdir() {
    mkdir -p "$1"
    OUTDIR=$(cd "$1" && pwd)
    LOGDIR="$OUTDIR/logs"
    RES="$OUTDIR/results"
    mkdir -p "$LOGDIR"
}

# load_samplesheet [only_sample]: reads columns by header name and collects
# every problem rather than stopping at the first.
load_samplesheet() {
    local only=${1:-} found=0 line lineno=1 i name all_ids=()
    local c_id c_type c_r1 c_r2 c_cond
    {
        IFS= read -r line || die "samplesheet is empty: $SHEET"
        line=${line%$'\r'}
        IFS=, read -r -a HEADER <<< "$line"
        for i in "${!HEADER[@]}"; do HEADER[$i]=$(trim "${HEADER[$i]}"); done
        for name in sample_id library_type r1_fastq r2_fastq; do
            if [[ $(col_index "$name") == -1 ]]; then add_error "samplesheet header has no '$name' column"; fi
        done
        report_errors "samplesheet header"
        c_id=$(col_index sample_id); c_type=$(col_index library_type)
        c_r1=$(col_index r1_fastq);  c_r2=$(col_index r2_fastq)
        c_cond=$(col_index condition)
        while IFS= read -r line || [[ -n "$line" ]]; do
            lineno=$((lineno + 1))
            line=${line%$'\r'}
            if [[ -z "${line//[[:space:],]/}" ]]; then continue; fi
            local f=() id type r1raw r2raw cond dup=0 j tag
            IFS=, read -r -a f <<< "$line"
            id=$(trim "${f[$c_id]:-}")
            type=$(trim "${f[$c_type]:-}" | tr '[:upper:]' '[:lower:]')
            r1raw=$(trim "${f[$c_r1]:-}")
            r2raw=$(trim "${f[$c_r2]:-}")
            cond=""; if (( c_cond >= 0 )); then cond=$(trim "${f[$c_cond]:-}"); fi
            tag="sample '$id' (line $lineno)"
            if [[ -z "$id" ]]; then tag="line $lineno"; add_error "$tag: sample_id is empty"; fi
            for ((j = 0; j < ${#all_ids[@]}; j++)); do
                if [[ -n "$id" && "${all_ids[$j]}" == "$id" ]]; then dup=1; fi
            done
            if (( dup )); then add_error "$tag: duplicate sample_id '$id' — it appears more than once"; fi
            case "$type" in
                paired) if [[ -z "$r2raw" ]]; then add_error "$tag: library_type is paired but r2_fastq is empty"; fi ;;
                single) if [[ -n "$r2raw" ]]; then add_error "$tag: library_type is single but r2_fastq is set ($r2raw)"; fi ;;
                *)      add_error "$tag: library_type must be 'paired' or 'single', got '$type'" ;;
            esac
            if [[ -z "$r1raw" ]]; then add_error "$tag: r1_fastq is empty"; fi
            if [[ -n "$id" ]] && (( ! dup )); then
                all_ids+=("$id")
                if [[ -z "$only" || "$id" == "$only" ]]; then
                    found=1
                    IDS+=("$id"); TYPES+=("$type"); CONDS+=("$cond")
                    R1S+=("$(resolve_path "$r1raw")"); R2S+=("$(resolve_path "$r2raw")")
                fi
            fi
        done
    } < "$SHEET"
    if [[ -n "$only" ]] && (( ! found )); then
        add_error "sample '$only' is not in the samplesheet $SHEET"
    elif (( ${#IDS[@]} == 0 && NERR == 0 )); then
        add_error "samplesheet has no sample rows"
    fi
}

check_environment() {
    local missing=() t dict contig
    for t in fastqc fastp bwa samtools gatk multiqc; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    if (( ${#missing[@]} > 0 )); then die "tools not on PATH: ${missing[*]} (is the conda environment active?)"; fi
    [[ -s "$REF" ]]     || die "REF not found: $REF"
    [[ -s "$REF.fai" ]] || die "reference index missing: $REF.fai"
    [[ -s "$REF.bwt" ]] || die "BWA index missing: $REF.bwt"
    dict="${REF%.*}.dict"
    [[ -s "$dict" ]]    || die "sequence dictionary missing: $dict"
    contig=${REGION%%:*}
    awk -v c="$contig" '$1 == c { f = 1 } END { exit !f }' "$REF.fai" \
        || die "REGION contig '$contig' is not in $REF.fai"
    mkdir -p "$TMPDIR"
    log "environment OK: REF=$REF REGION=$REGION THREADS=$THREADS TMPDIR=$TMPDIR"
}

source_stages() {
    local f
    for f in "$1"/stages/[0-9][0-9]_*.sh; do
        source "$f"
    done
}
