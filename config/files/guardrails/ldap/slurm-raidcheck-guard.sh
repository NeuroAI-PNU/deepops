#!/usr/bin/env bash
# slurm-raidcheck-guard.sh — drain compute nodes while this host's md RAID is
# REBUILDING, and resume them when it finishes.
#
# Why state-based instead of a timer: mdcheck runs monthly but is split across
# mdcheck_start / mdcheck_continue, so the *end* time is not predictable. We poll
# /proc/mdstat and act on transitions only.
#
# Safety: resume touches ONLY nodes whose drain Reason is exactly the one we set,
# so a node drained for any other purpose (hardware fault, maintenance) stays down.
#
# Runs as a systemd service on the NFS/home server (ldap).
set -uo pipefail

REASON="raid check"                 # must match what an admin/this script sets
NODES="neuroai[1-5],ldap"               # compute nodes served by this host's /home
INTERVAL="${RAIDGUARD_INTERVAL:-300}"
STATEFILE=/run/slurm-raidcheck-guard.state

log() { echo "$(date '+%F %T') $*"; }

# Deliberately NOT matching 'check': the monthly scrub (mdcheck) is a throttled
# read-only verification that runs 6h/day for several days at a randomized hour,
# so draining on it cost ~18h/month of scheduling availability while only blocking
# NEW jobs (running jobs keep hitting /home anyway). resync/recovery/reshape mean the
# array is actually being rebuilt and is vulnerable — that is worth draining for.
# Only the array backing /home matters. Matching all of /proc/mdstat drained the
# whole cluster for ~75 min after the 2026-09-28 reboot because the OS NVMe IMSM
# mirror (md124) resyncs on boot while /home (md126) was clean.
HOME_MD=$(basename "$(findmnt -no SOURCE /home 2>/dev/null)")
[[ $HOME_MD == md* ]] || HOME_MD=md126
raid_busy() {
    awk -v md="$HOME_MD" '/^md/ {cur = $1} cur == md && /resync|recovery|reshape/ {f = 1} END {exit !f}' \
        /proc/mdstat 2>/dev/null
}

# scontrol can fail on an early boot (name resolution / slurmctld not up yet). It
# silently did once, leaving nodes undrained through a 14h resync because the state
# file had already advanced. Only report success when scontrol actually succeeds so
# the caller can retry on the next poll.
sc() { scontrol "$@" 2>&1 | sed 's/^/  /'; return "${PIPESTATUS[0]}"; }

# Space-separated node names currently drained/down with our reason.
drained_by_us() {
    sinfo -N -h -o '%N|%T|%E' 2>/dev/null \
      | awk -F'|' -v r="$REASON" '$2 ~ /drain|down/ && $3 == r {print $1}' \
      | sort -u | paste -sd,
}

prev=$(cat "$STATEFILE" 2>/dev/null || echo idle)
log "guard started (interval=${INTERVAL}s, prev=$prev)"

while :; do
    if raid_busy; then
        if [ "$prev" != busy ]; then
            log "RAID activity detected -> draining $NODES"
            if sc update NodeName="$NODES" State=DRAIN Reason="$REASON"; then
                echo busy > "$STATEFILE"; prev=busy
            else
                log "drain FAILED (scontrol error) - will retry next poll"
            fi
        fi
    else
        if [ "$prev" = busy ]; then
            targets=$(drained_by_us)
            if [ -n "$targets" ]; then
                log "RAID idle -> resuming $targets"
                if sc update NodeName="$targets" State=RESUME; then
                    echo idle > "$STATEFILE"; prev=idle
                else
                    log "resume FAILED (scontrol error) - will retry next poll"
                fi
            else
                log "RAID idle -> nothing drained by us; leaving nodes alone"
                echo idle > "$STATEFILE"; prev=idle
            fi
        fi
    fi
    sleep "$INTERVAL"
done
