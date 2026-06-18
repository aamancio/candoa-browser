#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${CANDOA_E2E_DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${CANDOA_DERIVED_DATA_PATH:-}"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/candoa-e2e-site.XXXXXX")"
FIXTURE_PORT="${CANDOA_E2E_PORT:-18765}"
FIXTURE_PID=""
XCODEBUILD_ARGS=(
  -project Candoa.xcodeproj
  -scheme Candoa
  -configuration Debug
  -destination "$DESTINATION"
)

if [[ "${CANDOA_E2E_ADHOC_SIGNING:-0}" == "1" ]]; then
  XCODEBUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  )
fi

if [[ -n "$DERIVED_DATA_PATH" ]]; then
  XCODEBUILD_ARGS+=(-derivedDataPath "$DERIVED_DATA_PATH")
fi

cleanup() {
  if [[ -n "$FIXTURE_PID" ]]; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

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

cat > "$FIXTURE_DIR/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Candoa E2E Fixture</title>
  </head>
  <body>
    <main>
      <h1>Candoa E2E Fixture</h1>
      <p>Stable local page for UI navigation tests.</p>
    </main>
  </body>
</html>
HTML

cp "$FIXTURE_DIR/index.html" "$FIXTURE_DIR/first-run.html"
cp "$FIXTURE_DIR/index.html" "$FIXTURE_DIR/address.html"
cp "$FIXTURE_DIR/index.html" "$FIXTURE_DIR/new-tab.html"

python3 -m http.server "$FIXTURE_PORT" --bind 127.0.0.1 --directory "$FIXTURE_DIR" >/tmp/candoa-e2e-http.log 2>&1 &
FIXTURE_PID="$!"
export CANDOA_E2E_BASE_URL="http://127.0.0.1:$FIXTURE_PORT"

xcodebuild "${XCODEBUILD_ARGS[@]}" test
