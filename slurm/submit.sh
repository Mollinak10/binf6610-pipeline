#!/usr/bin/env bash
# submit.sh — two sbatch calls and one dependency.
# Run it from anywhere: it changes into slurm/ so $SLURM_SUBMIT_DIR is slurm/.
#   bash slurm/submit.sh                 one task per samplesheet row
#   ARRAY=1-2 bash slurm/submit.sh       override the array range
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

source conf/slurm.env
mkdir -p logs                                   # sbatch does not create the --output folder

N=$(awk 'NR > 1 && NF' "${SAMPLESHEET}" | wc -l)
N=${N//[[:space:]]/}
ARRAY=${ARRAY:-1-${N}}

ARRAY_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" --array="${ARRAY}" 01_persample.sbatch)
ARRAY_ID=${ARRAY_ID%%;*}
echo "per-sample array: ${ARRAY_ID}  (tasks ${ARRAY}, ${N} rows in the samplesheet)" >&2

COHORT_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes 02_cohort.sbatch)
COHORT_ID=${COHORT_ID%%;*}
echo "cohort job:       ${COHORT_ID}  (starts after every task succeeds: afterok)" >&2
echo "watch with:       squeue -u ${USER}" >&2
