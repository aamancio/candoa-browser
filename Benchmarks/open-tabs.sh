#!/bin/bash
# Opens the benchmark tab set in the given browser, one tab per URL.
#
# Usage: ./open-tabs.sh "Brave Browser"
#        ./open-tabs.sh Arc
#
# Note: if a browser is not registered as an http(s) handler (early Luma
# builds may not be), open the URLs manually instead — what matters is that
# every browser ends up with the identical tab set.
set -euo pipefail

APP=${1:?usage: open-tabs.sh <app-name>}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while IFS= read -r url; do
  [[ -z "$url" || "$url" == \#* ]] && continue
  open -a "$APP" "$url"
  sleep 2
done < "$SCRIPT_DIR/urls.txt"

echo "Opened benchmark tab set in $APP."
