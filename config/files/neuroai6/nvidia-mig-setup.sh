#!/usr/bin/env bash
# neuroai6: recreate the MIG layout at boot (MIG mode persists, GPU/compute instances do not).
# Since 2026-11-18 both cards: 4x 1g.24gb (profile 14) each = 8 slices. gres.conf uses NVML autodetection
# only, so instance IDs / /dev/nvidia-caps minors do not matter any more; only the count does.
# Runs before slurmd (nvidia-mig-setup.service). Idempotent: leaves a correct layout alone.
set -euo pipefail
UUIDS="GPU-c2be2c34-f8fd-a40b-d14a-107920d56b53 GPU-1c9d3825-e836-f08e-7f60-e5b11f0dfe6a"   # PCI 5D:00.0, DA:00.0
log() { echo "nvidia-mig-setup: $*"; }
rc=0
for uuid in $UUIDS; do
  idx=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader | awk -F', ' -v u="$uuid" '$2==u{print $1}')
  [ -n "$idx" ] || { log "GPU $uuid not found"; rc=1; continue; }
  if [ "$(nvidia-smi -i "$idx" --query-gpu=mig.mode.current --format=csv,noheader)" != "Enabled" ]; then
    log "enabling MIG on GPU $idx"; nvidia-smi -i "$idx" -mig 1
  fi
  n=$(nvidia-smi mig -i "$idx" -lgi 2>/dev/null | grep -c "MIG 1g.24gb" || true)
  if [ "$n" != 4 ]; then
    log "GPU $idx has $n 1g.24gb instances, rebuilding"
    nvidia-smi mig -i "$idx" -dci >/dev/null 2>&1 || true
    nvidia-smi mig -i "$idx" -dgi >/dev/null 2>&1 || true
    nvidia-smi mig -i "$idx" -cgi 14,14,14,14 -C
    n=$(nvidia-smi mig -i "$idx" -lgi 2>/dev/null | grep -c "MIG 1g.24gb" || true)
  fi
  if [ "$n" = 4 ]; then log "OK: GPU $idx MIG 4x 1g.24gb"; else log "ERROR: GPU $idx has $n instances"; rc=1; fi
done
exit $rc
