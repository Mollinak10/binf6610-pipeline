#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -J pull-variant-call
#SBATCH -o pull-%j.out
# Fetch the pipeline image onto Explorer as a .sif. A job, not the login node:
# converting the image peaks near 8 GiB of memory.
set -euo pipefail
# The download cache goes on /scratch: the home quota is fixed and cannot grow.
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p "${APPTAINER_CACHEDIR}" /scratch/${USER}/containers
apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://mollina/variant-call@sha256:40521a6fc6b9c880bd917a0f196038b5420f253524e95a2a4354ff95392ad151
apptainer exec --cleanenv /scratch/${USER}/containers/variant-call.sif samtools --version
