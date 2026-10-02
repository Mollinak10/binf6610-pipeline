# Image — Assignment 3

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

## The pushed image
docker.io/mollina/variant-call@sha256:40521a6fc6b9c880bd917a0f196038b5420f253524e95a2a4354ff95392ad151

Built on my laptop with `docker build --platform linux/amd64` from containers/Dockerfile and pushed as mollina/variant-call:1.0. On Explorer, slurm/pull.sbatch (job 10766305, 3:35, peak MaxRSS 9298288K) pulled it by digest into /scratch/kaul.mo/containers/variant-call.sif, and the cohort ran through it (array 10766428, cohort 10766436).

To rerun this in a year, what is needed is the image under "The pushed image": pulling by that digest returns exactly this image, every package included, even after /scratch has been emptied and the tag 1.0 has been moved. "Versions pinned" says what was asked for, and "Base image" says what it was built on, but rebuilding from the Dockerfile would not give the same image: the dependencies that are not pinned (htslib, Java, Python and the rest) resolve to whatever is newest on build day. The repository commit recorded in the manifest's git_sha (cf77e22), the course reference and the samplesheet are needed as well.
