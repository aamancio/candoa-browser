#!/usr/bin/env bash
# Makes the hero media for talos-browser.app from a clean workspace:
#
#   Scripts/site-screenshots.sh [path/to/Talos.app]
#
# For light and then dark, launches the app with the `site-showcase`
# UI-testing fixture (a temporary, local-only store with Work and Personal
# Spaces and a favourites row, so nothing personal is on screen), opens a
# few pages so their favicons load, captures the window as the poster
# (site/public/screenshots/talos-<appearance>.webp), then records a ~24 s
# scripted tour of the window (command bar, tab switcher, split view,
# sidebar, Spaces) and encodes it as talos-<appearance>.mp4. The tour is
# driven through the UI-testing window commands, never synthetic input,
# and it ends on the state it started from so the loop is seamless.
#
# Needs a built Debug app (default: the autobuild path), ffmpeg, and the
# sharp package pnpm installed in site/. Recording is window-only
# (Scripts/record-window.swift, ScreenCaptureKit), so other windows and the
# pointer never appear and the Mac stays usable while it runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/DerivedData/Build/Products/Debug/Talos.app}"
BIN="$APP/Contents/MacOS/Talos"
OUT="$ROOT/site/public/screenshots"
WORK="$(mktemp -d)"
SHARP="$(ls -d "$ROOT"/site/node_modules/.pnpm/sharp@*/node_modules/sharp | head -1)"
CMD="app.talos.uitesting.window-command"
SWITCHER="app.talos.uitesting.tab-switcher"

[ -x "$BIN" ] || { echo "No app at $APP. Build Debug first (Scripts/autobuild.sh)." >&2; exit 1; }
[ -d "$SHARP" ] || { echo "sharp is missing; run pnpm install in site/." >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is missing (brew install ffmpeg)." >&2; exit 1; }
mkdir -p "$OUT"

# A tiny helper that posts a distributed notification, compiled once.
cat > "$WORK/notify.swift" <<'EOF'
import Foundation
let a = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(a[1]), object: a[2], userInfo: nil, deliverImmediately: true)
EOF
swiftc -O -o "$WORK/notify" "$WORK/notify.swift"
n() { "$WORK/notify" "$1" "$2"; }
swiftc -O -framework ScreenCaptureKit -framework AVFoundation -framework AppKit \
  -o "$WORK/record-window" "$ROOT/Scripts/record-window.swift"

window_of() {
  swift -e 'import CoreGraphics; import Foundation
    let pid = Int32(CommandLine.arguments[1])!
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == pid && (w["kCGWindowLayer"] as? Int) == 0 {
      print(w["kCGWindowNumber"]!); break }' "$1"
}

run() {
  local appearance="$1" fixture="site-showcase"
  [ "$appearance" = dark ] && fixture="site-showcase-dark"
  TALOS_UI_TESTING=1 TALOS_UI_TESTING_FIXTURE="$fixture" TALOS_UI_TESTING_STORE_ID="site-media-$appearance" \
    "$BIN" -Talos.Settings.ZenOption.WebsiteAppearance "$appearance" >"$WORK/$appearance.log" 2>&1 &
  local pid=$!
  sleep 7
  # Personal gets one loaded page so the Space switch has something to show.
  n "$CMD" "space:next"; sleep 1
  open -a "$APP" "https://developer.apple.com/design/human-interface-guidelines"; sleep 4
  n "$CMD" "space:previous"; sleep 1
  for url in "https://webkit.org/" "https://developer.apple.com/documentation/webkit" "https://github.com/aamancio/talos-browser"; do
    open -a "$APP" "$url"; sleep 3
  done
  sleep 8
  local wnum
  wnum="$(window_of "$pid")"

  screencapture -x -o -l "$wnum" "$WORK/$appearance.png"
  "$WORK/record-window" "$wnum" 26 "$WORK/$appearance.mov" >"$WORK/$appearance.record.log" 2>&1 &
  local rec=$!
  sleep 1.5
  # The tour. Sleeps are what the viewer sees; keep the total near 24 s.
  sleep 2.0
  n "$CMD" "palette:type:webkit"; sleep 0.8; n "$CMD" "palette:type:webkit"; sleep 2.6
  n "$CMD" "palette:close"; sleep 0.6
  n "$SWITCHER" "next"; sleep 1.6
  n "$SWITCHER" "release"; sleep 2.0
  n "$CMD" "split:https://webkit.org/blog/"; sleep 4.5
  n "$CMD" "split:close"; sleep 0.3; n "$CMD" "tab:at:6"; sleep 0.3
  n "$CMD" "tab:close-url:https://webkit.org/blog"; sleep 1.2
  n "$CMD" "sidebar:toggle"; sleep 2.0
  n "$CMD" "sidebar:toggle"; sleep 1.5
  n "$CMD" "space:next"; sleep 2.5
  n "$CMD" "space:previous"; sleep 1.2
  n "$CMD" "tab:at:5"; sleep 2.0
  wait "$rec" || true
  kill "$pid"; sleep 2

  node -e '
    const sharp = require(process.argv[1]);
    sharp(process.argv[2]).resize({ width: 2400 }).webp({ quality: 82, alphaQuality: 90 }).toFile(process.argv[3]).then(() => console.log(process.argv[3]));
  ' "$SHARP" "$WORK/$appearance.png" "$OUT/talos-$appearance.webp"
  ffmpeg -y -v error -ss 1.5 -i "$WORK/$appearance.mov" -an -vf "scale=1920:-2,fps=30" \
    -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -movflags +faststart "$OUT/talos-$appearance.mp4"
  echo "$OUT/talos-$appearance.mp4"
}

run light
run dark
rm -rf "$WORK"
