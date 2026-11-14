#!/usr/bin/env bash
# Per-job directory on the node-local /scratch (neuroai6: RAID1 NVMe, ~6.8 TB).
# /scratch/<user>/<jobid>, mode 0700, removed by epilog.d/20-scratch-jobdir.
# Exported to the job as $SCRATCH_JOB by task_prolog.sh. No-op on nodes without /scratch.
set -eu
mountpoint -q /scratch || exit 0
u="${SLURM_JOB_USER:?}"; j="${SLURM_JOB_ID:?}"
[[ "$j" =~ ^[0-9]+$ ]] || exit 0
g=$(id -gn "$u")
install -d -o "$u" -g "$g" -m 0700 "/scratch/$u"
install -d -o "$u" -g "$g" -m 0700 "/scratch/$u/$j"
