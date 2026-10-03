#!/usr/bin/env bash
# home-usage-probe.sh - per-directory size of /home (top level), once a night.
#
# WHY NIGHTLY AND NOT A QUOTA: /dev/md126 is ext4 WITHOUT the quota feature
# (tune2fs -l shows none) and enabling it needs the filesystem unmounted - a
# maintenance-window job. Until then this is the only per-user number we have.
#
# WHY CAREFUL: on 2026-09-11 a recursive grep over /home pinned the RAID at 100%
# and made every node's sshd hang on authorized_keys (NFS). du only stats (no
# data reads), but 32M inodes on a 3-disk HDD RAID5 is still hours of random IO.
# So: 01:30 only, idle IO class, skip if md is resyncing/checking, and never
# Persistent= (a missed run must not fire at 10:00).
#
# Reads the LOCAL path (/srv/nfs4/home), not the NFS mount.
set -uo pipefail
ROOT=/srv/nfs4/home
OUT=/run/prometheus/home_usage.prom
KEEP=/var/lib/home-usage/last.prom     # /run is tmpfs; this copy is restored after reboot
TMP="$OUT.$$"
mkdir -p /run/prometheus "$(dirname "$KEEP")"
trap 'rm -f "$TMP"' EXIT

# Only the array backing /home matters (md124 = OS NVMe mirror; it resyncs after reboots).
HOME_MD=$(basename "$(findmnt -no SOURCE /home 2>/dev/null)"); [[ $HOME_MD == md* ]] || HOME_MD=md126
md_busy=$(awk -v md="$HOME_MD" '/^md/ {cur = $1} cur == md && match($0, /(resync|recovery|reshape|check) *= *[0-9.]+%/) {print substr($0, RSTART, RLENGTH); exit}' /proc/mdstat)
if [[ -n $md_busy ]]; then
  echo "$HOME_MD busy ($md_busy); skipping tonight" >&2
  exit 0
fi

start=$(date +%s)
{
  echo "# HELP home_dir_bytes Apparent disk usage of each top-level /home directory (du, nightly). kind=user if the name is an account."
  echo "# TYPE home_dir_bytes gauge"
} > "$TMP"

# One du invocation, one filesystem, idle IO priority.
while read -r bytes path; do
  d=$(basename "$path")
  [ "$d" = "lost+found" ] && continue
  owner=$(stat -c %U "$path" 2>/dev/null || echo unknown)
  if getent passwd "$d" >/dev/null 2>&1; then kind=user; else kind=shared; fi
  printf 'home_dir_bytes{dir="%s",owner="%s",kind="%s"} %s\n' "$d" "$owner" "$kind" "$bytes" >> "$TMP"
done < <(ionice -c3 nice -n19 du -s --block-size=1 --one-file-system "$ROOT"/*/ 2>/dev/null)

end=$(date +%s)
{
  echo "# HELP home_probe_duration_seconds Wall time of the nightly du."
  echo "# TYPE home_probe_duration_seconds gauge"
  echo "home_probe_duration_seconds $((end-start))"
  echo "# HELP home_probe_timestamp Unix time of the last successful probe run."
  echo "# TYPE home_probe_timestamp gauge"
  echo "home_probe_timestamp $end"
} >> "$TMP"
chmod 644 "$TMP"
cp -f "$TMP" "$KEEP"
mv -f "$TMP" "$OUT"
