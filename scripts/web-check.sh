#!/bin/bash
# Web export check: exports the demo project for the web, then plays it in headless Chrome (web/test/browser.js),
# failing on any page error. Swift ⇄ JS parity runs in `swift test` (WebParityTests).
# Usage: scripts/web-check.sh [outDir]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$(mktemp -d)}"
swift build
BIN="$(swift build --show-bin-path)/Lakon"
rm -rf "$OUT/demo"
"$BIN" --make-sample "$OUT/demo" >/dev/null
"$BIN" --export-web "$OUT/demo" "$OUT/web"
node web/test/browser.js "$OUT/web/Lakon Demo-web" web/test/steps-full.json "$OUT/shots"
echo "screenshots in $OUT/shots"
