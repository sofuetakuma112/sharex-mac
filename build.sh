#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build.noindex"
APP="$BUILD_DIR/ShareX.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --arch arm64

/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ShareXMac" "$APP/Contents/MacOS/ShareX"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/CaptureSound.wav" "$ROOT/Resources/TaskCompletedSound.wav" "$APP/Contents/Resources/"

ICONSET="$BUILD_DIR/AppIcon.iconset"
/bin/rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -s format png "$ROOT/Resources/ShareX_Icon.ico" --out "$BUILD_DIR/icon.png" >/dev/null
for size in 16 32 128 256; do
  sips -z "$size" "$size" "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$BUILD_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" --identifier local.sharex.mac "$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  /bin/rm -rf "$HOME/Applications/ShareX.app"
  cp -R "$APP" "$HOME/Applications/ShareX.app"
  echo "Installed: $HOME/Applications/ShareX.app"
else
  echo "Built: $APP"
fi
