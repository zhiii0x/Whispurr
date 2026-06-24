#!/bin/bash
# Build a styled Whispurr install DMG: cozy background, the app on the left, a
# paw-trail arrow pointing to an Applications alias on the right.
#
# Requires dist/Whispurr.app (run scripts/package.sh first).
# The Finder-styling step needs Automation permission the first time
# (System Settings → Privacy & Security → Automation → allow Terminal → Finder).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Whispurr"
VOL_NAME="${VOL_NAME:-Whispurr}"
VERSION="${VERSION:-0.1.0}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
RW="$DIST/$APP_NAME-rw.dmg"
STAGE="$DIST/dmg-stage"

# Window + icon geometry. The icon centres below MUST match the plinth centres
# in make-dmg-background.swift (left {165,200}, right {435,200}).
WIN_X=220; WIN_Y=140; WIN_W=600; WIN_H=400; ICON=120
WIN_R=$((WIN_X + WIN_W)); WIN_B=$((WIN_Y + WIN_H))

[ -d "$APP" ] || { echo "✗ $APP not found — run scripts/package.sh first"; exit 1; }

echo "▸ staging…"
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
swift "$ROOT/scripts/make-dmg-background.swift" "$STAGE/.background/background.png"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi

echo "▸ creating writable dmg…"
rm -f "$RW" "$DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ \
    -format UDRW -ov "$RW" >/dev/null

echo "▸ mounting…"
MOUNT="/Volumes/$VOL_NAME"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep '^/dev/' | head -1 | awk '{print $1}')"
sleep 2

# Volume icon = app icon (needs the custom-icon attribute set).
if [ -f "$MOUNT/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT" || true
fi

echo "▸ styling window (Finder)…"
osascript <<APPLESCRIPT || echo "  ⚠︎ Finder styling skipped (grant Automation: Terminal → Finder, then re-run)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $WIN_R, $WIN_B}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON
    set text size of opts to 12
    set background picture of opts to file ".background:background.png"
    delay 1
    set position of item "$APP_NAME.app" of container window to {165, 200}
    set position of item "Applications" of container window to {435, 200}
    delay 1
    update without registering applications
    delay 2
    close
    open
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync; sleep 1
echo "▸ finalizing…"
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"; rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    # Notarize + staple the DMG itself: stapling the inner app is NOT enough — a
    # downloaded (quarantined) DMG needs its own ticket or Gatekeeper warns on open.
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "▸ notarizing dmg…"
        SUBMIT_ID="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
            --wait --output-format json | tee /dev/stderr \
            | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
        xcrun notarytool log "$SUBMIT_ID" --keychain-profile "$NOTARY_PROFILE" || true
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
        spctl -a -vvv -t open --context context:primary-signature "$DMG"
    fi
fi
echo "✓ $DMG"
