#!/usr/bin/env bash
# run_pipeline.sh — ten-stage variant-calling pipeline (BINF6610, week 1)
#
# Usage:  run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]
# Stages: validate qc_raw trim align postprocess quantify merge analyze qc_report publish
#
# Written for bash 3.2 (macOS default) as well as bash 4/5:
# no associative arrays, no mapfile, no ${var,,}.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}
JAVA_MEM=${JAVA_MEM:-2g}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# Per-sample data, filled by stage 0 from the samplesheet (the only input)
IDS=(); TYPES=(); R1S=(); R2S=(); CONDS=()
HEADER=()

# ---------------------------------------------------------------- helpers
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
    echo "usage: $0 <samplesheet.csv> <outdir> [last_stage]" >&2
    echo "stages: ${STAGES[*]}" >&2
    exit 2
}

trim() {  # strip leading/trailing whitespace, keep inner spaces ("Donor 3-rep1")
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

col_index() {  # print the index of a header column, or -1
    local name=$1 i
    for i in "${!HEADER[@]}"; do
        if [[ "${HEADER[$i]}" == "$name" ]]; then echo "$i"; return 0; fi
    done
    echo -1
}

resolve_path() {  # absolute path; relative paths are tried from $PWD, then from the sheet's folder
    local p=$1
    if [[ -z "$p" ]]; then echo ""
    elif [[ "$p" == /* ]]; then echo "$p"
    elif [[ -e "$p" ]]; then echo "$PWD/$p"
    else echo "$SHEET_DIR/$p"
    fi
}

need_file() {  # assert a tool produced a non-empty output
    [[ -s "$1" ]] || die "$2: expected output is missing or empty: $1"
}

run() {  # run a tool, send its chatter to a log file; on failure show the log tail
    local logf=$1; shift
    if ! "$@" >>"$logf" 2>&1; then
        tail -n 20 "$logf" >&2
        die "command failed: $1 (full log: $logf)"
    fi
}

gatk_() { gatk --java-options "-Xmx${JAVA_MEM}" "$@"; }

fq_stem() {  # smoke_01_R1.fastq.gz -> smoke_01_R1 (FastQC's naming)
    local b; b=$(basename "$1")
    b=${b%.gz}; b=${b%.fastq}; b=${b%.fq}
    printf '%s' "$b"
}

# ---------------------------------------------------------------- stage 0
stage_validate() {
    local errors=() nerr=0 line lineno=1 i
    local c_id c_type c_r1 c_r2 c_cond name

    [[ -f "$SHEET" ]] || die "samplesheet not found: $SHEET"
    log "stage 0: validating $SHEET"

    {
        IFS= read -r line || die "samplesheet is empty: $SHEET"
        line=${line%$'\r'}
        IFS=, read -r -a HEADER <<< "$line"
        for i in "${!HEADER[@]}"; do HEADER[$i]=$(trim "${HEADER[$i]}"); done

        for name in sample_id library_type r1_fastq r2_fastq; do
            if [[ $(col_index "$name") == -1 ]]; then
                errors+=("samplesheet header has no '$name' column"); nerr=$((nerr + 1))
            fi
        done
        if (( nerr > 0 )); then
            for i in "${!errors[@]}"; do log "  PROBLEM: ${errors[$i]}"; done
            die "stage 0 failed: $nerr problem(s) in the samplesheet header"
        fi
        c_id=$(col_index sample_id); c_type=$(col_index library_type)
        c_r1=$(col_index r1_fastq);  c_r2=$(col_index r2_fastq)
        c_cond=$(col_index condition)

        while IFS= read -r line || [[ -n "$line" ]]; do
            lineno=$((lineno + 1))
            line=${line%$'\r'}
            if [[ -z "${line//[[:space:],]/}" ]]; then continue; fi   # blank line

            local f=()
            IFS=, read -r -a f <<< "$line"
            local id type r1 r2 cond r1raw r2raw n1="" n2="" dup=0 r1ok=0 r2ok=0 j
            id=$(trim "${f[$c_id]:-}")
            type=$(trim "${f[$c_type]:-}" | tr '[:upper:]' '[:lower:]')
            r1raw=$(trim "${f[$c_r1]:-}")
            r2raw=$(trim "${f[$c_r2]:-}")
            cond=""; if (( c_cond >= 0 )); then cond=$(trim "${f[$c_cond]:-}"); fi
            r1=$(resolve_path "$r1raw"); r2=$(resolve_path "$r2raw")

            local tag="sample '$id' (line $lineno)"
            if [[ -z "$id" ]]; then
                tag="line $lineno"
                errors+=("$tag: sample_id is empty"); nerr=$((nerr + 1))
            fi

            # duplicate sample_id
            for ((j = 0; j < ${#IDS[@]}; j++)); do
                if [[ -n "$id" && "${IDS[$j]}" == "$id" ]]; then dup=1; fi
            done
            if (( dup )); then
                errors+=("$tag: duplicate sample_id '$id' — it appears more than once"); nerr=$((nerr + 1))
            fi

            # layout comes from library_type; r2_fastq must agree with it
            case "$type" in
                paired)
                    if [[ -z "$r2raw" ]]; then
                        errors+=("$tag: library_type is paired but r2_fastq is empty"); nerr=$((nerr + 1))
                    fi ;;
                single)
                    if [[ -n "$r2raw" ]]; then
                        errors+=("$tag: library_type is single but r2_fastq is set ($r2raw)"); nerr=$((nerr + 1))
                    fi ;;
                *)
                    errors+=("$tag: library_type must be 'paired' or 'single', got '$type'"); nerr=$((nerr + 1)) ;;
            esac

            # R1: present, readable, a complete gzip stream
            if [[ -z "$r1raw" ]]; then
                errors+=("$tag: r1_fastq is empty"); nerr=$((nerr + 1))
            elif [[ ! -r "$r1" ]]; then
                errors+=("$tag: R1 file not found: $r1raw"); nerr=$((nerr + 1))
            elif ! gzip -t "$r1" 2>/dev/null; then
                errors+=("$tag: R1 is not a complete gzip file (truncated or corrupt): $r1raw"); nerr=$((nerr + 1))
            else
                r1ok=1
            fi

            # R2, only when the layout is paired and a path was given
            if [[ "$type" == paired && -n "$r2raw" ]]; then
                if [[ ! -r "$r2" ]]; then
                    errors+=("$tag: R2 file not found: $r2raw"); nerr=$((nerr + 1))
                elif ! gzip -t "$r2" 2>/dev/null; then
                    errors+=("$tag: R2 is not a complete gzip file (truncated or corrupt): $r2raw"); nerr=$((nerr + 1))
                else
                    r2ok=1
                fi
            fi

            # data assertions: line count divisible by 4, R1/R2 agree
            if (( r1ok )); then
                if ! n1=$(gzip -dc "$r1" | wc -l); then n1=0; fi
                n1=${n1//[[:space:]]/}
                if (( n1 == 0 )); then
                    errors+=("$tag: R1 contains no reads"); nerr=$((nerr + 1))
                elif (( n1 % 4 != 0 )); then
                    errors+=("$tag: R1 has $n1 lines, not a multiple of 4"); nerr=$((nerr + 1))
                fi
            fi
            if (( r2ok )); then
                if ! n2=$(gzip -dc "$r2" | wc -l); then n2=0; fi
                n2=${n2//[[:space:]]/}
                if (( n2 % 4 != 0 )); then
                    errors+=("$tag: R2 has $n2 lines, not a multiple of 4"); nerr=$((nerr + 1))
                fi
                if (( r1ok )) && [[ "$n1" != "$n2" ]]; then
                    errors+=("$tag: R1 has $((n1 / 4)) reads but R2 has $((n2 / 4))"); nerr=$((nerr + 1))
                fi
            fi

            if [[ -n "$id" ]] && (( ! dup )); then
                IDS+=("$id"); TYPES+=("$type"); R1S+=("$r1"); R2S+=("$r2"); CONDS+=("$cond")
                if (( r1ok )); then
                    log "  checked '$id': $type-end, $((n1 / 4)) reads in R1${cond:+, condition=$cond}"
                fi
            fi
        done
    } < "$SHEET"

    if (( ${#IDS[@]} == 0 && nerr == 0 )); then
        errors+=("samplesheet has no sample rows"); nerr=$((nerr + 1))
    fi

    if (( nerr > 0 )); then
        for i in "${!errors[@]}"; do log "  PROBLEM: ${errors[$i]}"; done
        die "stage 0 failed: $nerr problem(s) found — fix all of them and rerun"
    fi
    log "stage 0: OK — ${#IDS[@]} sample(s) validated"
}

check_environment() {  # only needed when stages past validate will run
    local missing=() t dict contig
    for t in fastqc fastp bwa samtools gatk multiqc; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    if (( ${#missing[@]} > 0 )); then die "tools not on PATH: ${missing[*]} (did you activate the conda env?)"; fi

    [[ -s "$REF" ]]     || die "REF not found: $REF"
    [[ -s "$REF.fai" ]] || die "reference index missing: $REF.fai"
    [[ -s "$REF.bwt" ]] || die "BWA index missing: $REF.bwt"
    dict="${REF%.*}.dict"
    [[ -s "$dict" ]]    || die "sequence dictionary missing: $dict"
    contig=${REGION%%:*}
    awk -v c="$contig" '$1 == c { f = 1 } END { exit !f }' "$REF.fai" \
        || die "REGION contig '$contig' is not in $REF.fai"
    log "environment OK: REF=$REF REGION=$REGION THREADS=$THREADS"
}

# ---------------------------------------------------------------- stages 1-9
stage_qc_raw() {
    local d="$OUTDIR/01_qc_raw" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} r1=${R1S[$i]} r2=${R2S[$i]}
        log "  FastQC: $id"
        if [[ "${TYPES[$i]}" == paired ]]; then
            run "$LOGDIR/01_fastqc.$id.log" fastqc -q -t "$THREADS" -o "$d" "$r1" "$r2"
            need_file "$d/$(fq_stem "$r2")_fastqc.zip" "qc_raw $id"
        else
            run "$LOGDIR/01_fastqc.$id.log" fastqc -q -t "$THREADS" -o "$d" "$r1"
        fi
        need_file "$d/$(fq_stem "$r1")_fastqc.zip" "qc_raw $id"
    done
}

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

stage_align() {
    local t="$OUTDIR/02_trim" d="$OUTDIR/03_align" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} logf="$LOGDIR/03_align.${IDS[$i]}.log"
        local reads=("$t/$id.R1.trim.fastq.gz")
        if [[ "${TYPES[$i]}" == paired ]]; then reads+=("$t/$id.R2.trim.fastq.gz"); fi
        log "  bwa mem: $id"
        # pipefail makes this `if` see a bwa failure, not just samtools' status
        if ! bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA" "$REF" "${reads[@]}" 2>>"$logf" \
             | samtools sort -@ "$THREADS" -o "$d/$id.sorted.bam" - 2>>"$logf"; then
            tail -n 20 "$logf" >&2
            die "align $id: bwa mem | samtools sort failed (log: $logf)"
        fi
        need_file "$d/$id.sorted.bam" "align $id"
        local n; n=$(samtools view -c "$d/$id.sorted.bam")
        (( n > 0 )) || die "align $id: BAM has no records"
        log "    $n alignments"
    done
}

stage_postprocess() {
    local a="$OUTDIR/03_align" d="$OUTDIR/04_postprocess" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} logf="$LOGDIR/04_markdup.${IDS[$i]}.log"
        log "  index + MarkDuplicates: $id"
        run "$logf" samtools index "$a/$id.sorted.bam"
        run "$logf" gatk_ MarkDuplicates -I "$a/$id.sorted.bam" \
            -O "$d/$id.markdup.bam" -M "$d/$id.markdup.metrics.txt"
        need_file "$d/$id.markdup.bam" "postprocess $id"
        run "$logf" samtools index "$d/$id.markdup.bam"
        need_file "$d/$id.markdup.bam.bai" "postprocess $id"
    done
}

stage_quantify() {
    local p="$OUTDIR/04_postprocess" d="$OUTDIR/05_quantify" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]}
        log "  HaplotypeCaller -ERC GVCF: $id"
        run "$LOGDIR/05_hc.$id.log" gatk_ HaplotypeCaller -R "$REF" \
            -I "$p/$id.markdup.bam" -O "$d/$id.g.vcf.gz" -L "$REGION" -ERC GVCF
        need_file "$d/$id.g.vcf.gz" "quantify $id"
    done
}

stage_merge() {
    local q="$OUTDIR/05_quantify" d="$OUTDIR/06_merge" i args=()
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do args+=(-V "$q/${IDS[$i]}.g.vcf.gz"); done
    log "  CombineGVCFs: ${#IDS[@]} samples"
    run "$LOGDIR/06_merge.log" gatk_ CombineGVCFs -R "$REF" "${args[@]}" \
        -L "$REGION" -O "$d/cohort.g.vcf.gz"
    need_file "$d/cohort.g.vcf.gz" "merge"
    log "  GenotypeGVCFs"
    run "$LOGDIR/06_merge.log" gatk_ GenotypeGVCFs -R "$REF" \
        -V "$d/cohort.g.vcf.gz" -L "$REGION" -O "$d/cohort.vcf.gz"
    need_file "$d/cohort.vcf.gz" "merge"
}

stage_analyze() {
    local in="$OUTDIR/06_merge/cohort.vcf.gz" d="$OUTDIR/07_analyze" logf="$LOGDIR/07_filter.log"
    mkdir -p "$d"
    log "  hard-filtering SNPs and indels separately (GATK recommended thresholds)"
    run "$logf" gatk_ SelectVariants -R "$REF" -V "$in" --select-type-to-include SNP -O "$d/snps.vcf.gz"
    run "$logf" gatk_ VariantFiltration -R "$REF" -V "$d/snps.vcf.gz" -O "$d/snps.filtered.vcf.gz" \
        --filter-expression "QD < 2.0"              --filter-name "QD2" \
        --filter-expression "QUAL < 30.0"           --filter-name "QUAL30" \
        --filter-expression "SOR > 3.0"             --filter-name "SOR3" \
        --filter-expression "FS > 60.0"             --filter-name "FS60" \
        --filter-expression "MQ < 40.0"             --filter-name "MQ40" \
        --filter-expression "MQRankSum < -12.5"     --filter-name "MQRankSum-12.5" \
        --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8"
    run "$logf" gatk_ SelectVariants -R "$REF" -V "$in" \
        --select-type-to-include INDEL --select-type-to-include MIXED -O "$d/indels.vcf.gz"
    run "$logf" gatk_ VariantFiltration -R "$REF" -V "$d/indels.vcf.gz" -O "$d/indels.filtered.vcf.gz" \
        --filter-expression "QD < 2.0"               --filter-name "QD2" \
        --filter-expression "QUAL < 30.0"            --filter-name "QUAL30" \
        --filter-expression "FS > 200.0"             --filter-name "FS200" \
        --filter-expression "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20"
    run "$logf" gatk_ MergeVcfs -I "$d/snps.filtered.vcf.gz" -I "$d/indels.filtered.vcf.gz" \
        -O "$d/cohort.filtered.vcf.gz"
    need_file "$d/cohort.filtered.vcf.gz" "analyze"
    log "  final VCF: $d/cohort.filtered.vcf.gz"
}

stage_qc_report() {
    local d="$OUTDIR/08_qc_report"
    mkdir -p "$d"
    log "  MultiQC across the cohort"
    run "$LOGDIR/08_multiqc.log" multiqc -f -o "$d" "$OUTDIR/01_qc_raw" "$OUTDIR/02_trim" "$OUTDIR/04_postprocess"
    need_file "$d/multiqc_report.html" "qc_report"
}

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

# ---------------------------------------------------------------- driver
main() {
    [[ $# -ge 2 && $# -le 3 ]] || usage
    SHEET=$1
    OUTDIR=$2
    local to=${3:-publish} last=-1 s

    for s in "${!STAGES[@]}"; do
        if [[ "${STAGES[$s]}" == "$to" ]]; then last=$s; fi
    done
    (( last >= 0 )) || die "unknown stage '$to' (choose from: ${STAGES[*]})"

    SHEET_DIR=$(cd "$(dirname "$SHEET")" && pwd)
    SHEET="$SHEET_DIR/$(basename "$SHEET")"
    mkdir -p "$OUTDIR"
    OUTDIR=$(cd "$OUTDIR" && pwd)
    LOGDIR="$OUTDIR/logs"
    RES="$OUTDIR/results"
    mkdir -p "$LOGDIR"

    log "=== stage 0: validate ==="
    stage_validate
    if (( last == 0 )); then log "stopping after validate"; return 0; fi

    check_environment
    for ((s = 1; s <= last; s++)); do
        log "=== stage $s: ${STAGES[$s]} ==="
        "stage_${STAGES[$s]}"
    done
    log "done: stages 0-$last finished; outputs in $OUTDIR"
}

main "$@"
