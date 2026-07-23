#!/usr/bin/env bash
# Slurm TaskProlog: lines printed as "export NAME=VALUE" are injected into the job task env.
# For shard jobs, point CUDA MPS client env at this user's per-user MPS pipe (started by prolog.d/55-mps).
# Runs as the job user. Must never fail the task -> always exit 0.
jobid="${SLURM_JOB_ID:-${SLURM_JOBID:-}}"
[ -z "$jobid" ] && exit 0
if scontrol show job "$jobid" 2>/dev/null | grep -qiE 'gres[:/]shard'; then
    uid=$(id -u)
    echo "export CUDA_MPS_PIPE_DIRECTORY=/dev/shm/nvidia-mps-${uid}"
    echo "export CUDA_MPS_LOG_DIRECTORY=/dev/shm/nvidia-mps-log-${uid}"
fi
exit 0
