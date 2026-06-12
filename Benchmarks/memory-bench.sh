#!/bin/bash
# Memory benchmark: samples the total resident memory of a browser's process
# tree over time. No sudo needed.
#
# The interesting shape for Luma is the hibernation cliff: open the tab set,
# run this for 35+ minutes, and total memory drops as idle tabs give up their
# WebContent processes (15 min idle threshold + scan interval). Chromium and
# Gecko browsers stay flat or grow.
#
# Usage:
#   ./memory-bench.sh <label> <process-pattern> [duration-seconds]
#
# Presets (match battery-bench.sh):
#   ./memory-bench.sh luma  'Luma|com.apple.WebKit'  2400
#   ./memory-bench.sh arc   'Arc'                    2400
#   ./memory-bench.sh brave 'Brave'                  2400
#   ./memory-bench.sh zen   'zen|plugin-container'   2400
#
# Protocol: see README.md. One browser at a time, identical tab set, do not
# touch the browser while sampling (interacting resets idle timers).
set -euo pipefail

LABEL=${1:?usage: memory-bench.sh <label> <process-pattern> [duration-seconds]}
PATTERN=${2:?usage: memory-bench.sh <label> <process-pattern> [duration-seconds]}
DURATION=${3:-2400}
SAMPLE_INTERVAL=15

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/results"
mkdir -p "$OUT_DIR"
SERIES="$OUT_DIR/$LABEL-memory.csv"
SUMMARY="$OUT_DIR/memory-summary.csv"

echo "Sampling resident memory for '$PATTERN' every ${SAMPLE_INTERVAL}s for ${DURATION}s..."
echo "elapsed_s,total_rss_mb,process_count" > "$SERIES"

END=$((SECONDS + DURATION))
START=$SECONDS
while (( SECONDS < END )); do
  ps -Ao rss=,command= \
    | awk -v pattern="$PATTERN" -v elapsed="$((SECONDS - START))" '
        $0 ~ pattern { kb += $1; count += 1 }
        END { printf "%d,%.0f,%d\n", elapsed, kb / 1024, count }
      ' >> "$SERIES"
  sleep "$SAMPLE_INTERVAL"
done

read -r FIRST_MB PEAK_MB FINAL_MB AVG_MB < <(awk -F, '
  NR == 2 { first = $2 }
  NR > 1 {
    if ($2 > peak) peak = $2
    sum += $2; n += 1; final = $2
  }
  END { printf "%.0f %.0f %.0f %.0f\n", first, peak, final, (n ? sum / n : 0) }
' "$SERIES")

[[ -f "$SUMMARY" ]] || echo "label,duration_s,first_mb,peak_mb,final_mb,avg_mb" > "$SUMMARY"
echo "$LABEL,$DURATION,$FIRST_MB,$PEAK_MB,$FINAL_MB,$AVG_MB" >> "$SUMMARY"

echo
echo "── $LABEL ─────────────────────────────────────────"
echo "  First sample:  ${FIRST_MB} MB"
echo "  Peak:          ${PEAK_MB} MB"
echo "  Final:         ${FINAL_MB} MB   <- hibernation shows up here"
echo "  Average:       ${AVG_MB} MB"
echo "  Time series:   $SERIES"
echo "  Appended to:   $SUMMARY"
