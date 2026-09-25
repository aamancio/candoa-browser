#!/usr/bin/env bash
# Captures the hero screenshots for talos-browser.app from a clean workspace.
#
#   Scripts/site-screenshots.sh [path/to/Talos.app]
#
# Launches the app with the `site-showcase` UI-testing fixture (a temporary,
# local-only store with Work and Personal Spaces and a favourites row, so
# nothing personal is on screen), opens three pages so their favicons load,
# captures the window by id, and encodes site/public/screenshots/*.webp.
# Runs once with light chrome and light websites, once with dark. Needs a
# built Debug app; the default is the autobuild path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/DerivedData/Build/Products/Debug/Talos.app}"
BIN="$APP/Contents/MacOS/Talos"
WORK="$(mktemp -d)"
OUT="$ROOT/site/public/screenshots"
SHARP="$(ls -d "$ROOT"/site/node_modules/.pnpm/sharp@*/node_modules/sharp | head -1)"

[ -x "$BIN" ] || { echo "No app at $APP. Build Debug first (Scripts/autobuild.sh)." >&2; exit 1; }
[ -d "$SHARP" ] || { echo "sharp is missing; run pnpm install in site/." >&2; exit 1; }
mkdir -p "$OUT"

capture() {
  local fixture="$1" appearance="$2" out="$3"
  TALOS_UI_TESTING=1 TALOS_UI_TESTING_FIXTURE="$fixture" TALOS_UI_TESTING_STORE_ID="site-shot-$appearance" \
    "$BIN" -Talos.Settings.ZenOption.WebsiteAppearance "$appearance" >"$WORK/$appearance.log" 2>&1 &
  local pid=$!
  sleep 7
  for url in "https://www.apple.com/macos/" "https://developer.apple.com/documentation/webkit" "https://github.com/aamancio/talos-browser"; do
    open -a "$APP" "$url"
    sleep 3
  done
  sleep 10
  local wid
  wid="$(swift -e 'import CoreGraphics; import Foundation
    let pid = Int32(CommandLine.arguments[1])!
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == pid && (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"]!); break }' "$pid")"
  screencapture -x -o -l "$wid" "$out"
  kill "$pid"
  sleep 2
}

capture site-showcase light "$WORK/light.png"
capture site-showcase-dark dark "$WORK/dark.png"

node -e '
const sharp = require(process.argv[1]); const work = process.argv[2]; const out = process.argv[3];
(async () => { for (const v of ["light", "dark"]) {
  await sharp(`${work}/${v}.png`).resize({ width: 2400 }).webp({ quality: 82, alphaQuality: 90 }).toFile(`${out}/talos-${v}.webp`);
  console.log(`${out}/talos-${v}.webp`);
} })();
' "$SHARP" "$WORK" "$OUT"
rm -rf "$WORK"
