#!/bin/bash
# Watches Candoa's Swift sources and rebuilds on every change.
#
#   Scripts/autobuild.sh          # build on change
#   Scripts/autobuild.sh --run    # build on change, then relaunch the app
#
# Uses fswatch when installed (brew install fswatch); otherwise falls back
# to a 2-second polling loop with no dependencies.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/Candoa"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Candoa.app"
RELAUNCH=false
FSWATCH_BIN="$(command -v fswatch 2>/dev/null || true)"
CANDOA_PROCESS_NAME="Candoa"
LOCK_DIR="/tmp/candoa-autobuild.lock"

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR"' EXIT
        return 0
    fi

    local existing_pid
    existing_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Candoa autobuild is already running (pid $existing_pid)"
        exit 0
    fi

    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"
    trap 'rm -rf "$LOCK_DIR"' EXIT
}

if [[ -z "$FSWATCH_BIN" && -x /opt/homebrew/bin/fswatch ]]; then
    FSWATCH_BIN=/opt/homebrew/bin/fswatch
elif [[ -z "$FSWATCH_BIN" && -x /usr/local/bin/fswatch ]]; then
    FSWATCH_BIN=/usr/local/bin/fswatch
fi

if [[ "${1:-}" == "--run" ]]; then
    RELAUNCH=true
fi

acquire_lock

is_candoa_running() {
    pgrep -x "$CANDOA_PROCESS_NAME" >/dev/null 2>&1
}

quit_candoa() {
    if ! is_candoa_running; then
        return 0
    fi

    osascript -e 'tell application "Candoa" to quit' 2>/dev/null || true

    for _ in {1..40}; do
        if ! is_candoa_running; then
            return 0
        fi
        sleep 0.25
    done

    echo "✗ Candoa is still running; skipping relaunch to avoid duplicate app instances"
    return 1
}

open_candoa() {
    for _ in {1..20}; do
        if open "$APP_PATH" >/dev/null 2>&1; then
            for _ in {1..20}; do
                if is_candoa_running; then
                    return 0
                fi
                sleep 0.25
            done
        fi
        sleep 0.25
    done

    echo "✗ Failed to reopen Candoa after build"
    return 1
}

build() {
    echo "▸ Building…"
    local output
    # Branch on xcodebuild's own exit code: piping straight into grep under
    # pipefail reports the build's failure status even when grep matched,
    # which inverted success/failure here.
    if output=$(xcodebuild -project "$PROJECT_DIR/Candoa.xcodeproj" -scheme Candoa \
        -configuration Debug -derivedDataPath "$DERIVED_DATA" build 2>&1); then
        echo "✓ Build succeeded $(date +%H:%M:%S)"
    else
        echo "$output" | grep -E "error:" | head -10
        echo "✗ Build failed $(date +%H:%M:%S)"
        return 1
    fi

    if $RELAUNCH; then
        # Quit cleanly so the session flushes. If the old app is still
        # exiting, do not open a second copy of the rebuilt app.
        if quit_candoa; then
            open_candoa
        fi
    fi
}

echo "Watching $SOURCE_DIR (Ctrl-C to stop)"
build

if [[ -n "$FSWATCH_BIN" ]]; then
    # Coalesce bursts of writes (Xcode/editors save several files at once).
    "$FSWATCH_BIN" --one-per-batch --latency 0.5 \
        --include '\.swift$' --exclude '.*' "$SOURCE_DIR" |
    while read -r _; do
        build
    done
else
    echo "(fswatch not installed — using a 2s polling fallback; brew install fswatch for instant triggers)"
    # Hash only the sources. Comparing against DerivedData here re-triggered
    # forever, because every build updates DerivedData itself.
    LAST_STATE="$(find "$SOURCE_DIR" -name '*.swift' -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum)"
    while true; do
        STATE="$(find "$SOURCE_DIR" -name '*.swift' -exec stat -f '%m %N' {} + 2>/dev/null | sort | shasum)"
        if [[ "$STATE" != "$LAST_STATE" ]]; then
            LAST_STATE="$STATE"
            build
        fi
        sleep 2
    done
fi
