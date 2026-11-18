#!/usr/bin/env bash
# neuroai6: recreate the MIG layout on GPU1 at boot (MIG mode persists, GPU/compute instances do not).
# Layout: 4x 1g.24gb (profile 14). /etc/slurm/gres.conf lists the slices by /dev/nvidia-caps files that
# follow from GPU instance IDs 3-6, so the script checks it got exactly those IDs.
# Runs before slurmd (nvidia-mig-setup.service). Idempotent: leaves an existing correct layout alone.
set -euo pipefail
UUID=GPU-1c9d3825-e836-f08e-7f60-e5b11f0dfe6a   # GPU1, PCI DA:00.0
WANT_IDS="3 4 5 6"
log() { echo "nvidia-mig-setup: $*"; }

idx=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader | awk -F', ' -v u="$UUID" '$2==u{print $1}')
[ -n "$idx" ] || { log "GPU $UUID not found"; exit 1; }

if [ "$(nvidia-smi -i "$idx" --query-gpu=mig.mode.current --format=csv,noheader)" != "Enabled" ]; then
  log "enabling MIG on GPU $idx"; nvidia-smi -i "$idx" -mig 1
fi

gi_ids() { nvidia-smi mig -i "$idx" -lgi 2>/dev/null | awk '/MIG 1g.24gb/{print $6}' | sort -n | tr '\n' ' ' | sed 's/ $//'; }
have=$(gi_ids)
if [ "$have" != "$WANT_IDS" ]; then
  log "GPU instances now: '${have:-none}', rebuilding"
  nvidia-smi mig -i "$idx" -dci >/dev/null 2>&1 || true
  nvidia-smi mig -i "$idx" -dgi >/dev/null 2>&1 || true
  nvidia-smi mig -i "$idx" -cgi 14,14,14,14 -C
  have=$(gi_ids)
fi
if [ "$have" != "$WANT_IDS" ]; then
  log "ERROR: GPU instance IDs are '$have', gres.conf expects '$WANT_IDS' - fix /etc/slurm/gres.conf cap files"
  exit 1
fi
log "OK: GPU $idx MIG 4x 1g.24gb, instance IDs $have"
