#!/bin/bash
# Generate AppIcon.icns from a cat frame, centred on the cozy background.
# Usage: scripts/make-icon.sh [source.png] [out.icns]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/Sources/WhispurrApp/Resources/CatFrames/idle.png}"
OUT="${2:-$ROOT/dist/AppIcon.icns}"
BG="${ICON_BG:-EFE9F6}"   # soft lavender to match the onboarding backdrop

WORK="$(mktemp -d)"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"

# Scale the cat to leave a margin, then pad to a 1024 square on the background.
sips -s format png "$SRC" --resampleHeightWidthMax 820 --out "$WORK/cat.png" >/dev/null
sips "$WORK/cat.png" --padToHeightWidth 1024 1024 --padColor "$BG" --out "$WORK/base.png" >/dev/null

emit() { sips -z "$2" "$2" "$WORK/base.png" --out "$SET/$1" >/dev/null; }
emit icon_16x16.png        16
emit icon_16x16@2x.png     32
emit icon_32x32.png        32
emit icon_32x32@2x.png     64
emit icon_128x128.png     128
emit icon_128x128@2x.png  256
emit icon_256x256.png     256
emit icon_256x256@2x.png  512
emit icon_512x512.png     512
emit icon_512x512@2x.png 1024

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$SET" -o "$OUT"
rm -rf "$WORK"
echo "icon → $OUT"
