#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
APP_NAME="sharex-mac"
BUNDLE_ID="io.github.sofuetakuma112.sharex-mac"
BUILD_DIR="$ROOT/build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --arch arm64

/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/SharexMac" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/CaptureSound.wav" "$ROOT/Resources/TaskCompletedSound.wav" "$APP/Contents/Resources/"

ICONSET="$BUILD_DIR/AppIcon.iconset"
/bin/rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  /bin/rm -rf "$HOME/Applications/$APP_NAME.app"
  cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
  echo "Installed: $HOME/Applications/$APP_NAME.app"
else
  echo "Built: $APP"
fi
