#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Grok Plan Switcher"
EXECUTABLE="GrokPlanSwitcher"
BUNDLE_ID="com.local.grok-plan-switcher"
MIN_SYSTEM_VERSION="13.0"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ICONSET="$ROOT_DIR/.build/GrokPlanSwitcher.iconset"
SWIFT_BUILD_DIR="$(mktemp -d /private/tmp/grok-plan-switcher-package.XXXXXX)"
trap 'rm -rf "$SWIFT_BUILD_DIR" "${WORK_DIR:-}"' EXIT

mkdir -p "$ROOT_DIR/.build/ModuleCache" "$DIST_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
cd "$ROOT_DIR"
# Keep build-machine paths out of the shipped binary.
PREFIX_MAP=(-Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=." -Xswiftc -file-prefix-map -Xswiftc "$SWIFT_BUILD_DIR=build")
swift build -c release --arch arm64 --arch x86_64 "${PREFIX_MAP[@]}" \
  --scratch-path "$SWIFT_BUILD_DIR" --cache-path "$ROOT_DIR/.build/cache" \
  --manifest-cache local --disable-sandbox
BUILD_BINARY="$(swift build -c release --arch arm64 --arch x86_64 "${PREFIX_MAP[@]}" \
  --scratch-path "$SWIFT_BUILD_DIR" --cache-path "$ROOT_DIR/.build/cache" \
  --manifest-cache local --disable-sandbox --show-bin-path)/$EXECUTABLE"

strip -S -x "$BUILD_BINARY"
rm -rf "$APP_BUNDLE" "$ICONSET"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$ICONSET"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
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
/usr/bin/python3 - "$ICONSET" "$APP_RESOURCES/AppIcon.icns" <<'PY'
import pathlib
import struct
import sys

iconset = pathlib.Path(sys.argv[1])
chunks = []
for name, kind in (
    ("icon_16x16.png", "icp4"),
    ("icon_16x16@2x.png", "ic11"),
    ("icon_32x32.png", "icp5"),
    ("icon_32x32@2x.png", "ic12"),
    ("icon_128x128.png", "ic07"),
    ("icon_128x128@2x.png", "ic13"),
    ("icon_256x256.png", "ic08"),
    ("icon_256x256@2x.png", "ic14"),
    ("icon_512x512.png", "ic09"),
    ("icon_512x512@2x.png", "ic10"),
):
    data = (iconset / name).read_bytes()
    chunks.append(kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

payload = b"".join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
PY

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force -s - "$APP_BUNDLE"
fi

WORK_DIR="$(mktemp -d "$DIST_DIR/.dmg-work.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
RAW_IMAGE="$WORK_DIR/source.dmg"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil makehybrid -hfs -hfs-volume-name "$APP_NAME" -o "$RAW_IMAGE" "$STAGING_DIR"
hdiutil convert -format UDZO -ov -o "$DMG_PATH" "$RAW_IMAGE"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_RESULT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait)"
  printf '%s\n' "$NOTARY_RESULT"
  NOTARY_STATUS="$(printf '%s\n' "$NOTARY_RESULT" | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | tail -n 1)"
  if [[ "$NOTARY_STATUS" != Accepted ]]; then
    printf 'Notarization failed: %s\n' "$NOTARY_STATUS" >&2
    exit 1
  fi
  xcrun stapler staple "$DMG_PATH"
fi

printf '%s\n' "$DMG_PATH"
