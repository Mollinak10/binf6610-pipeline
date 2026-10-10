# Troubleshooting log — Assignment 4

## 1. Ctrl-C halfway through a smoke run, then -resume

Command: `nextflow run main.nf -profile docker -ansi-log false --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb --outdir results-b1`, stopped with Ctrl-C just after `[27/b24fdf] Submitted process > MARKDUPLICATES (smoke_01)`, then the same command with `-resume` (logs: b1-run1.txt, b1-run2.txt).

Output: 10 tasks were cached, with the same hashes as the first run: VALIDATE, FASTQC x3, FASTP x3 and BWA_MEM x3 (for example `[d3/16d2c7] Cached process > BWA_MEM (smoke_01)`). MARKDUPLICATES (smoke_01), which Ctrl-C interrupted, ran again in a new work folder (2f/56222e instead of 27/b24fdf), and so did everything downstream of it: MARKDUPLICATES x3, HAPLOTYPECALLER x3, JOINT_GENOTYPE, FILTER, MULTIQC and PUBLISH. Fix: none needed; -resume reuses every task that finished with unchanged inputs and script, and reruns only the unfinished ones.

Breakages 2-4 and the Explorer run were not finished by the deadline.
