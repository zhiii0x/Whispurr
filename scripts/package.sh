#!/bin/bash
# Build Whispurr into a signed .app (and optionally a notarized DMG).
#
#   scripts/package.sh                      # release build → dist/Whispurr.app (ad-hoc signed)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/package.sh   # Developer ID signed
#   SIGN_IDENTITY=… NOTARY_PROFILE=… MAKE_DMG=1 scripts/package.sh   # signed + notarized + stapled DMG
#
# NOTARY_PROFILE is a `notarytool` keychain profile created once with:
#   xcrun notarytool store-credentials NOTARY_PROFILE --apple-id you@example.com \
#         --team-id TEAMID --password <app-specific-password>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Whispurr"
BUNDLE_ID="tw.digilog.whispurr"
VERSION="${VERSION:-0.1.0}"
BUILD_NUM="${BUILD_NUM:-1}"
CONFIG="${CONFIG:-release}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Whispurr.entitlements"

echo "▸ building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BINDIR="$(swift build -c "$CONFIG" --product "$APP_NAME" --show-bin-path)"
BIN="$BINDIR/$APP_NAME"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUM</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whispurr listens to your voice locally to type what you say.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Whispurr transcribes your speech on-device to insert text.</string>
</dict>
</plist>
PLIST

# Resource bundle (CatFrames) — SwiftPM emits it next to the binary as
# <Package>_<Target>.bundle. Bundle.module finds it under Contents/Resources.
RES_BUNDLE="$(cd "$BINDIR" && ls -d ./*.bundle 2>/dev/null | head -1 || true)"
if [ -n "$RES_BUNDLE" ] && [ -d "$BINDIR/$RES_BUNDLE" ]; then
    cp -R "$BINDIR/$RES_BUNDLE" "$APP/Contents/Resources/"
else
    echo "  ⚠︎ no resource bundle found — cat frames will fall back to SF Symbols"
fi

echo "▸ icon…"
"$ROOT/scripts/make-icon.sh" "" "$APP/Contents/Resources/AppIcon.icns" || echo "  (icon generation skipped)"

echo "▸ signing…"
# Sign the app bundle in ONE pass — NOT with --deep (Apple advises against --deep
# for distribution; it over-entitles/mis-signs nested items). There is no nested
# executable here: the SwiftPM resource bundle is pure PNGs (no Mach-O, and not a
# real bundle — codesign can't sign it directly), so a single app-bundle sign
# correctly seals it as a resource AND embeds the entitlements + Hardened Runtime
# in the main binary.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    # guard: get-task-allow must be absent or notarization rejects the build
    if codesign -d --entitlements - --xml "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null | grep -q get-task-allow; then
        echo "✗ ERROR: get-task-allow present — would fail notarization"; exit 1
    fi
else
    echo "  no SIGN_IDENTITY → ad-hoc signing (runs locally; NOT notarizable)"
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
echo "  → $APP"

if [ -n "${NOTARY_PROFILE:-}" ] && [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "▸ notarizing…"
    ZIP="$DIST/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl -a -vvv --type exec "$APP"   # expect: accepted, source=Notarized Developer ID
    rm -f "$ZIP"
fi

if [ "${MAKE_DMG:-0}" = "1" ]; then
    echo "▸ styled dmg…"
    VERSION="$VERSION" VOL_NAME="$APP_NAME" SIGN_IDENTITY="${SIGN_IDENTITY:-}" \
        NOTARY_PROFILE="${NOTARY_PROFILE:-}" \
        "$ROOT/scripts/make-dmg.sh"
fi

echo "✓ done"
