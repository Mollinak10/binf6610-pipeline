#!/bin/bash -l
# Stages 6–9, once, after every array task has succeeded (submit.sh sets afterok).
# Orchestration only: the analysis lives in run_pipeline.sh.
#SBATCH --job-name=vc-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --export=NONE                          # start clean: take nothing from your login shell
#SBATCH --output=logs/cohort_%j.out            # submit.sh runs mkdir -p logs first
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder sbatch ran from: slurm/

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

export THREADS="${SLURM_CPUS_PER_TASK}"
export JAVA_MEM

set +u
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

FROM_STAGE=merge bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable) bytes" >&2
