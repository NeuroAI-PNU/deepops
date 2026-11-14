#!/usr/bin/env bash
# Daily /scratch housekeeping (scratch-cleanup.timer). /scratch has NO backup.
#  1. /scratch/<user>/<jobid> whose job is no longer running (epilog missed it, e.g. node crash)
#     and that is older than 1 day -> removed.
#  2. Everything else under /scratch/<user>/ (shared datasets, caches) that has been neither read
#     nor modified for SCRATCH_MAX_AGE_DAYS (default 30) -> removed; empty dirs pruned.
set -u
AGE="${SCRATCH_MAX_AGE_DAYS:-30}"
mountpoint -q /scratch || exit 0
# Job ids running here, space-padded. Empty string = squeue failed -> leave every job dir alone.
if out=$(squeue -h -w "$(hostname -s)" -o %A 2>/dev/null); then
  running=" $(echo $out) "
else
  echo "squeue failed; not touching job dirs"; running=""
fi
for udir in /scratch/*/; do
  udir=${udir%/}; [[ -L "$udir" || "$(basename "$udir")" == lost+found ]] && continue
  for jd in "$udir"/[0-9]*/; do
    [[ -d "$jd" ]] || continue; jd=${jd%/}; j=$(basename "$jd")
    [[ "$j" =~ ^[0-9]+$ ]] || continue
    if [[ -n "$running" && "$running" != *" $j "* ]] && [[ -n "$(find "$jd" -maxdepth 0 -mmin +1440)" ]]; then
      echo "orphan job dir: $jd"; rm -rf --one-file-system -- "$jd"
    fi
  done
  find "$udir" -xdev -mindepth 1 -type f -atime +"$AGE" -mtime +"$AGE" \
       -not -path "$udir/[0-9]*" -print -delete 2>/dev/null | sed 's/^/expired: /'
  find "$udir" -xdev -mindepth 1 -type d -empty -not -path "$udir/[0-9]*" -delete 2>/dev/null
done
