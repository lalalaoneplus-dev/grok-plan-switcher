#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Grok Plan Switcher"
EXECUTABLE="GrokPlanSwitcher"
BUNDLE_ID="com.local.grok-plan-switcher"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.svg"
ICONSET="$ROOT_DIR/.build/GrokPlanSwitcher.iconset"

pkill -f "$APP_BINARY" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$EXECUTABLE"
rm -rf "$APP_BUNDLE" "$ICONSET"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$ICONSET"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

sips -s format png "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
for variant in \
  "icon_16x16.png:16" "icon_16x16@2x.png:32" \
  "icon_32x32.png:32" "icon_32x32@2x.png:64" \
  "icon_128x128.png:128" "icon_128x128@2x.png:256" \
  "icon_256x256.png:256" "icon_256x256@2x.png:512" \
  "icon_512x512.png:512"
do
  name="${variant%%:*}"
  size="${variant##*:}"
  sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.4</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -f "$APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
