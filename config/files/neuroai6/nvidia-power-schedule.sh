#!/bin/sh
# neuroai6 (2026-11-20): GPU power limit by time of day (fan noise vs throughput).
# Day 08:00-20:59 -> DAY_W (300 W: two full cards ~8,400-8,900 rpm), night 21:00-07:59 -> NIGHT_W (400 W:
# ~20 % more throughput, but fans reach 11-12k rpm). 300 W is the card's minimum (range 300-600 W).
# Run at boot by nvidia-power-limit.service and at 08:00/21:00 by nvidia-power-limit.timer.
DAY_W=${DAY_W:-300}
NIGHT_W=${NIGHT_W:-400}
h=$(date +%H)
if [ "$h" -ge 21 ] || [ "$h" -lt 8 ]; then w=$NIGHT_W; else w=$DAY_W; fi
logger -t nvidia-power-schedule "hour $h -> ${w} W"
exec /usr/bin/nvidia-smi -pl "$w"
