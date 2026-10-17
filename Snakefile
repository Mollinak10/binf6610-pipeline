# variant-call: the ten stages of weeks 1-4 as Snakemake rules, connected by file names.
import csv
import os
import re

configfile: "config.yaml"

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]                                                       # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                             # smoke.dict, not smoke.fa.dict
REGION = config["region"]

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) if names else "(?!)"


def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]


def heap(wildcards, resources):
    """The Java heap: 80 % of the job's memory, leaving room outside the heap."""
    return int(resources.mem_mb * 0.8)


rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


# Stage 0 · validate — a copy of the samplesheet, made only if every check passes.
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"


# Stage 1 · qc_raw — FastQC on the reads as they arrived.
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    log:
        "logs/fastqc/{sample}.log",
    threads: 2
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -t {threads} -o {output} {input.reads}) 2> {log}"


# Stage 2 · trim — two rules with the same output names; each sample matches one.
rule fastp_paired:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    log:
        "logs/fastp/{sample}.log",
    wildcard_constraints:
        sample=one_of(PAIRED),
    threads: 4
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.reads[0]} -I {input.reads[1]} --detect_adapter_for_pe "
        "-o {output.r1} -O {output.r2} -j {output.json} -h {output.html} 2> {log}"


rule fastp_single:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    log:
        "logs/fastp/{sample}.log",
    wildcard_constraints:
        sample=one_of(SINGLE),
    threads: 4
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.reads[0]} "
        "-o {output.r1} -j {output.json} -h {output.html} 2> {log}"


# Stage 3 · align — BWA-MEM into a sorted BAM; SM is the sample, which names its VCF column.
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
    output:
        "work/align/{sample}.sorted.bam",
    log:
        "logs/bwa_mem/{sample}.log",
    threads: 8
    resources:
        mem_mb=2000,
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}\tPL:ILLUMINA' {input.ref} {input.reads} \
            | samtools sort -@ {threads} -T work/align/{wildcards.sample}.tmp -o {output} -) 2> {log}
        """


# Stage 4 · postprocess — mark duplicates, then index.
rule markduplicates:
    input:
        "work/align/{sample}.sorted.bam",
    output:
        bam="work/markdup/{sample}.markdup.bam",
        bai="work/markdup/{sample}.markdup.bam.bai",
        metrics="work/markdup/{sample}.markdup.metrics.txt",
    log:
        "logs/markduplicates/{sample}.log",
    threads: 2
    resources:
        mem_mb=2000,
    params:
        heap=heap,
    container: IMAGES["gatk"]
    shell:
        "(gatk --java-options '-Xmx{params.heap}m' MarkDuplicates -I {input} -O {output.bam} "
        "-M {output.metrics} --TMP_DIR work/markdup && samtools index {output.bam}) 2> {log}"


# Stage 5 · quantify — per-sample GVCF in the region.
rule haplotypecaller:
    input:
        bam="work/markdup/{sample}.markdup.bam",
        bai="work/markdup/{sample}.markdup.bam.bai",
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    log:
        "logs/haplotypecaller/{sample}.log",
    threads: 8
    resources:
        mem_mb=2000,
    params:
        heap=heap,
        region=REGION,
    container: IMAGES["gatk"]
    shell:
        "gatk --java-options '-Xmx{params.heap}m' HaplotypeCaller -R {input.ref} -I {input.bam} "
        "-O {output.gvcf} -L {params.region} -ERC GVCF --native-pair-hmm-threads {threads} "
        "--tmp-dir work/gvcf 2> {log}"


# Stage 6 · merge — joint genotyping across every sample's GVCF.
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    log:
        "logs/joint_genotype.log",
    threads: 2
    resources:
        mem_mb=2000,
    params:
        heap=heap,
        region=REGION,
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
    container: IMAGES["gatk"]
    shell:
        "(gatk --java-options '-Xmx{params.heap}m' CombineGVCFs -R {input.ref} {params.variants} "
        "-L {params.region} -O work/joint/cohort.g.vcf.gz --tmp-dir work/joint "
        "&& gatk --java-options '-Xmx{params.heap}m' GenotypeGVCFs -R {input.ref} "
        "-V work/joint/cohort.g.vcf.gz -L {params.region} -O {output.vcf} --tmp-dir work/joint) 2> {log}"


# Stage 7 · analyze — hard filters, SNPs and indels separately, and variants.tsv.
rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        ref_fai=REF_FAI,
        ref_dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    log:
        "logs/filter.log",
    threads: 2
    resources:
        mem_mb=2000,
    params:
        heap=heap,
    container: IMAGES["gatk"]
    shell:
        r"""
        (mkdir -p work/filter
        gatk --java-options '-Xmx{params.heap}m' SelectVariants -R {input.ref} -V {input.vcf} \
            --select-type-to-include SNP -O work/filter/snps.vcf.gz
        gatk --java-options '-Xmx{params.heap}m' VariantFiltration -R {input.ref} -V work/filter/snps.vcf.gz \
            -O work/filter/snps.filtered.vcf.gz \
            --filter-expression "QD < 2.0"              --filter-name "QD2" \
            --filter-expression "QUAL < 30.0"           --filter-name "QUAL30" \
            --filter-expression "SOR > 3.0"             --filter-name "SOR3" \
            --filter-expression "FS > 60.0"             --filter-name "FS60" \
            --filter-expression "MQ < 40.0"             --filter-name "MQ40" \
            --filter-expression "MQRankSum < -12.5"     --filter-name "MQRankSum-12.5" \
            --filter-expression "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8"
        gatk --java-options '-Xmx{params.heap}m' SelectVariants -R {input.ref} -V {input.vcf} \
            --select-type-to-include INDEL --select-type-to-include MIXED -O work/filter/indels.vcf.gz
        gatk --java-options '-Xmx{params.heap}m' VariantFiltration -R {input.ref} -V work/filter/indels.vcf.gz \
            -O work/filter/indels.filtered.vcf.gz \
            --filter-expression "QD < 2.0"               --filter-name "QD2" \
            --filter-expression "QUAL < 30.0"            --filter-name "QUAL30" \
            --filter-expression "FS > 200.0"             --filter-name "FS200" \
            --filter-expression "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20"
        gatk --java-options '-Xmx{params.heap}m' MergeVcfs -I work/filter/snps.filtered.vcf.gz \
            -I work/filter/indels.filtered.vcf.gz -O {output.vcf}
        printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}
        ) 2> {log}
        """


# Stage 8 · qc_report — MultiQC on the reports themselves, not on the whole project.
rule multiqc:
    input:
        fastqc=expand("work/fastqc/{sample}", sample=SAMPLES),
        fastp=expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        markdup=expand("work/markdup/{sample}.markdup.metrics.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input} && cp work/multiqc/multiqc_report.html {output}) 2> {log}"


# Stage 9 · publish — the course's rule, which writes samples.tsv and manifest.json.
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
