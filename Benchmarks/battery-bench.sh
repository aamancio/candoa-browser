#!/bin/bash
# Battery benchmark for browsers on Apple Silicon Macs.
#
# Measures two things over the run:
#   1. Average system package power (CPU+GPU+ANE, via powermetrics) — run on
#      an otherwise-idle machine so the browser dominates the number.
#   2. Average CPU% summed across all of the browser's processes (via ps) —
#      attributes load to the browser regardless of system noise.
#
# Usage (root required for powermetrics):
#   sudo ./battery-bench.sh <label> <process-pattern> [duration-seconds]
#
# Presets:
#   sudo ./battery-bench.sh baseline 'match-nothing^'                 600
#   sudo ./battery-bench.sh luma     'Luma|com.apple.WebKit'          600
#   sudo ./battery-bench.sh arc      'Arc'                            600
#   sudo ./battery-bench.sh brave    'Brave'                          600
#   sudo ./battery-bench.sh zen      'zen|plugin-container'           600
#
# Protocol: see README.md. One browser at a time, identical tab set,
# identical display brightness, no other apps running.
set -euo pipefail

LABEL=${1:?usage: battery-bench.sh <label> <process-pattern> [duration-seconds]}
PATTERN=${2:?usage: battery-bench.sh <label> <process-pattern> [duration-seconds]}
DURATION=${3:-600}
SAMPLE_INTERVAL=5

if [[ $EUID -ne 0 ]]; then
  echo "powermetrics needs root; run with sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/results"
mkdir -p "$OUT_DIR"
POWER_RAW="$OUT_DIR/$LABEL-power.txt"
CPU_RAW="$OUT_DIR/$LABEL-cpu.txt"
SUMMARY="$OUT_DIR/summary.csv"

echo "Benchmarking '$LABEL' (pattern: $PATTERN) for ${DURATION}s..."
echo "Keep the machine idle except for the browser under test."

powermetrics --samplers cpu_power \
  -i $((SAMPLE_INTERVAL * 1000)) \
  -n $((DURATION / SAMPLE_INTERVAL)) > "$POWER_RAW" &
POWER_PID=$!

: > "$CPU_RAW"
END=$((SECONDS + DURATION))
while (( SECONDS < END )); do
  ps -Ao %cpu=,command= \
    | awk -v pattern="$PATTERN" '$0 ~ pattern { sum += $1 } END { printf "%.1f\n", sum + 0 }' \
    >> "$CPU_RAW"
  sleep "$SAMPLE_INTERVAL"
done
wait "$POWER_PID" || true

AVG_POWER_MW=$(awk -F'[: ]+' '
  /Combined Power \(CPU \+ GPU \+ ANE\)/ { sum += $(NF-1); n += 1 }
  END { if (n) printf "%.0f", sum / n; else print "0" }
' "$POWER_RAW")

AVG_CPU=$(awk '{ sum += $1; n += 1 } END { if (n) printf "%.1f", sum / n; else print "0" }' "$CPU_RAW")

ENERGY_MWH=$(awk -v p="$AVG_POWER_MW" -v d="$DURATION" 'BEGIN { printf "%.1f", p * d / 3600 }')

[[ -f "$SUMMARY" ]] || echo "label,duration_s,avg_browser_cpu_percent,avg_package_power_mw,package_energy_mwh" > "$SUMMARY"
echo "$LABEL,$DURATION,$AVG_CPU,$AVG_POWER_MW,$ENERGY_MWH" >> "$SUMMARY"

echo
echo "── $LABEL ─────────────────────────────────────────"
echo "  Browser CPU (avg, all matching processes): ${AVG_CPU}%"
echo "  Package power (system-wide avg):           ${AVG_POWER_MW} mW"
echo "  Package energy over run:                   ${ENERGY_MWH} mWh"
echo "  Appended to ${SUMMARY}"
