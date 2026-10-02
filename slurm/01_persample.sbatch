#!/bin/bash -l
# Stages 0–5 for ONE sample, as one task of an array. Task N runs row N of the
# samplesheet. Orchestration only: the analysis lives in run_sample.sh.
#SBATCH --job-name=vc-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --export=NONE                          # start clean: take nothing from your login shell
#SBATCH --output=logs/persample_%A_%a.out      # submit.sh runs mkdir -p logs first
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"    # the folder sbatch ran from: slurm/

# Row N of the samplesheet, counting from the first row below the header
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }
echo "task ${SLURM_ARRAY_TASK_ID} -> sample '${SAMPLE}' on $(hostname)" >&2

# Temporary files on the node's own disk, removed however the job ends
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Cores come from Slurm, never typed as a number here
export THREADS="${SLURM_CPUS_PER_TASK}"
export JAVA_MEM

# The software comes from the image. --cleanenv starts it with none of this
# shell's variables; --env carries back the ones the pipeline reads; --bind
# makes the course data and the run directory visible inside.
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env JAVA_MEM="${JAVA_MEM}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

# Exact peak memory of this job
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable) bytes" >&2
