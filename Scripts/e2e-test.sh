#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${CANDOA_E2E_DESTINATION:-platform=macOS}"

cd "$ROOT_DIR"

stop_candoa_processes() {
  local signal="$1"
  local pids

  pids="$(pgrep -x Candoa || true)"
  if [[ -z "$pids" ]]; then
    return
  fi

  pkill "-$signal" -x Candoa || true

  while IFS= read -r pid; do
    local ppid
    local parent_command

    if [[ -z "$pid" ]]; then
      continue
    fi

    ppid="$(ps -o ppid= -p "$pid" | tr -d ' ')"
    parent_command="$(ps -o comm= -p "$ppid" 2>/dev/null || true)"

    if [[ "$parent_command" == *debugserver* ]]; then
      kill "-$signal" "$ppid" || true
    fi
  done <<< "$pids"
}

if pgrep -x Candoa >/dev/null; then
  stop_candoa_processes TERM

  for _ in {1..20}; do
    if ! pgrep -x Candoa >/dev/null; then
      break
    fi
    sleep 0.25
  done
fi

if pgrep -x Candoa >/dev/null; then
  stop_candoa_processes KILL

  for _ in {1..20}; do
    if ! pgrep -x Candoa >/dev/null; then
      break
    fi
    sleep 0.25
  done
fi

if pgrep -x Candoa >/dev/null; then
  echo "Candoa is still running. Quit Candoa before running E2E tests." >&2
  exit 1
fi

xcodebuild \
  -project Candoa.xcodeproj \
  -scheme Candoa \
  -configuration Debug \
  -destination "$DESTINATION" \
  test
