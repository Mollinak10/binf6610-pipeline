#!/usr/bin/env bash
# Stage 7: hard filters, SNPs and indels separately (GATK recommended thresholds).
set -euo pipefail

stage_analyze() {
    local in="$OUTDIR/06_merge/cohort.vcf.gz" d="$OUTDIR/07_analyze" logf="$LOGDIR/07_filter.log"
    mkdir -p "$d"
    need_file "$in" "analyze"
    log "  hard-filtering SNPs and indels separately"
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
