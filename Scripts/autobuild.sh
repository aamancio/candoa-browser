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

if [[ "${1:-}" == "--run" ]]; then
    RELAUNCH=true
fi

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
        # Quit (not kill -9) so the session flushes, then reopen the new build.
        osascript -e 'tell application "Candoa" to quit' 2>/dev/null
        sleep 0.5
        open "$APP_PATH"
    fi
}

echo "Watching $SOURCE_DIR (Ctrl-C to stop)"
build

if command -v fswatch >/dev/null 2>&1; then
    # Coalesce bursts of writes (Xcode/editors save several files at once).
    fswatch --one-per-batch --latency 0.5 \
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
