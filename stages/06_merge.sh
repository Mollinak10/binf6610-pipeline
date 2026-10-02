#!/usr/bin/env bash
# Stage 6: joint genotyping. Refuses to run unless every sample has its GVCF.
set -euo pipefail

stage_merge() {
    local q="$OUTDIR/05_quantify" d="$OUTDIR/06_merge" i args=() missing=()
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        if [[ -s "$q/${IDS[$i]}.g.vcf.gz" ]]; then args+=(-V "$q/${IDS[$i]}.g.vcf.gz")
        else missing+=("${IDS[$i]}")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        die "merge: no GVCF for ${#missing[@]} sample(s): ${missing[*]}"
    fi
    log "  CombineGVCFs: ${#IDS[@]} samples"
    run "$LOGDIR/06_merge.log" gatk_ CombineGVCFs -R "$REF" "${args[@]}" \
        -L "$REGION" -O "$d/cohort.g.vcf.gz"
    need_file "$d/cohort.g.vcf.gz" "merge"
    log "  GenotypeGVCFs"
    run "$LOGDIR/06_merge.log" gatk_ GenotypeGVCFs -R "$REF" \
        -V "$d/cohort.g.vcf.gz" -L "$REGION" -O "$d/cohort.vcf.gz"
    need_file "$d/cohort.vcf.gz" "merge"
}
