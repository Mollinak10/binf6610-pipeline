#!/usr/bin/env bash
# Stage 3: BWA-MEM alignment, sorted with samtools (temp files in $TMPDIR).
set -euo pipefail

stage_align() {
    local t="$OUTDIR/02_trim" d="$OUTDIR/03_align" i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        local id=${IDS[$i]} logf="$LOGDIR/03_align.${IDS[$i]}.log" n
        local reads=("$t/$id.R1.trim.fastq.gz")
        if [[ "${TYPES[$i]}" == paired ]]; then reads+=("$t/$id.R2.trim.fastq.gz"); fi
        log "  bwa mem: $id"
        if ! bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA" "$REF" "${reads[@]}" 2>>"$logf" \
             | samtools sort -@ "$THREADS" -T "$TMPDIR/sort.$id" -o "$d/$id.sorted.bam" - 2>>"$logf"; then
            tail -n 20 "$logf" >&2
            die "align $id: bwa mem | samtools sort failed (log: $logf)"
        fi
        need_file "$d/$id.sorted.bam" "align $id"
        n=$(samtools view -c "$d/$id.sorted.bam")
        (( n > 0 )) || die "align $id: BAM has no records"
        log "    $n alignments"
    done
}
