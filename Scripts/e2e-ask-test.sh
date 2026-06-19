#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${CANDOA_E2E_DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${CANDOA_DERIVED_DATA_PATH:-}"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/candoa-ask-e2e-site.XXXXXX")"
DERIVED_DATA_DIR=""
FIXTURE_PORT="${CANDOA_E2E_PORT:-18765}"
FIXTURE_PID=""
XCODEBUILD_ARGS=(
  -project Candoa.xcodeproj
  -scheme Candoa
  -configuration Debug
  -destination "$DESTINATION"
  -only-testing:CandoaUITests/CandoaAskUITests
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
  DERIVED_DATA_DIR="$DERIVED_DATA_PATH"
else
  DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/candoa-ask-e2e-derived.XXXXXX")"
fi

XCODEBUILD_ARGS+=(-derivedDataPath "$DERIVED_DATA_DIR")

cleanup() {
  if [[ -n "$FIXTURE_PID" ]]; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  rm -rf "$FIXTURE_DIR"
  if [[ -z "$DERIVED_DATA_PATH" && -n "$DERIVED_DATA_DIR" ]]; then
    rm -rf "$DERIVED_DATA_DIR"
  fi
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
  echo "Candoa is still running. Quit Candoa before running Ask E2E tests." >&2
  exit 1
fi

cat > "$FIXTURE_DIR/youtube.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>YouTube Fixture</title>
    <meta name="description" content="Deterministic YouTube-style page for Ask context tests.">
  </head>
  <body>
    <main>
      <h1>YouTube Fixture</h1>
      <p>YouTube fixture is a video-sharing test page for Ask context tests.</p>
      <p>Its unique context marker is streaming tutorials and channel subscriptions.</p>
      <p>This fixture must never be used when the attached context is the eBay fixture.</p>
    </main>
  </body>
</html>
HTML

cat > "$FIXTURE_DIR/ebay.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>eBay Fixture</title>
    <meta name="description" content="Deterministic eBay-style page for Ask context tests.">
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; }
      header { display: flex; gap: 24px; align-items: center; padding: 8px 14px; border-bottom: 1px solid #ddd; }
      main { padding: 48px 14px; }
    </style>
  </head>
  <body>
    <header>
      <p>Hi! <a href="/signin.html">Sign in</a> or <a href="/register.html">register</a></p>
      <nav>
        <a href="/deals.html">Deals</a>
        <a href="/help.html">Help & Contact</a>
      </nav>
    </header>
    <main>
      <h1>eBay Fixture</h1>
      <p>eBay fixture is a marketplace test page for Ask context tests.</p>
      <p>Its unique context marker is listings, auctions, carts, and seller ratings.</p>
      <p>This fixture must never be used when the attached context is the YouTube fixture.</p>
    </main>
  </body>
</html>
HTML

cat > "$FIXTURE_DIR/image-signin.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Image Sign In Fixture</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; padding: 16px; }
      img { width: 96px; height: 32px; background: #145be8; border-radius: 6px; display: block; }
    </style>
  </head>
  <body>
    <a href="/secure-signin.html"><img alt="Sign in with secure account"></a>
    <main>
      <h1>Image Sign In Fixture</h1>
      <p>This page uses image alt text as the only visible label for its login link.</p>
    </main>
  </body>
</html>
HTML

cat > "$FIXTURE_DIR/hidden-signin.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Hidden Sign In Fixture</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; padding: 16px; }
      .hidden { display: none; }
      header { display: flex; gap: 16px; align-items: center; }
    </style>
  </head>
  <body>
    <header>
      <a class="hidden" href="/signin.html">Sign in</a>
      <a href="/register.html">Register</a>
      <button>Search</button>
    </header>
    <main>
      <h1>Hidden Sign In Fixture</h1>
      <p>This page has a hidden sign-in link that must not be reported as visible.</p>
    </main>
  </body>
</html>
HTML

python3 -m http.server "$FIXTURE_PORT" --bind 127.0.0.1 --directory "$FIXTURE_DIR" >/tmp/candoa-ask-e2e-http.log 2>&1 &
FIXTURE_PID="$!"
export CANDOA_E2E_BASE_URL="http://127.0.0.1:$FIXTURE_PORT"

xcodebuild "${XCODEBUILD_ARGS[@]}" test
