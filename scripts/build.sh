#!/bin/zsh
# Builds StatMenu.app. Pass --install to copy it into /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK's SwiftUI needs macro plugins that only ship with full Xcode,
# so build against the newest SDK that works with Command Line Tools alone.
if ! xcode-select -p | grep -q Xcode.app; then
  for sdk in MacOSX26.5.sdk MacOSX26.sdk MacOSX15.sdk; do
    if [[ -d /Library/Developer/CommandLineTools/SDKs/$sdk ]]; then
      export SDKROOT=/Library/Developer/CommandLineTools/SDKs/$sdk
      break
    fi
  done
fi

swift build -c release --build-system native 2>&1 | grep -v "has been deprecated"

APP=build/StatMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --build-system native --show-bin-path 2>/dev/null)/StatMenu" "$APP/Contents/MacOS/StatMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

if [[ ! -f build/AppIcon.icns || scripts/make_icon.swift -nt build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift scripts/make_icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x StatMenu || true
  rm -rf /Applications/StatMenu.app
  cp -R "$APP" /Applications/
  open /Applications/StatMenu.app
  echo "Installed to /Applications/StatMenu.app"
fi
