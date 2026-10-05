#!/bin/bash
# Macdow.app 번들을 build/ 아래에 만든다.  사용법: ./build.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

# Command Line Tools에는 macOS 27 SDK의 SwiftUI 매크로(@State) 플러그인이 없어서,
# Xcode 없이 빌드할 때는 macOS 26 SDK로 대체한다.
if [[ -z "${SDKROOT:-}" ]] && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    FALLBACK_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
    if [[ -n "$FALLBACK_SDK" ]]; then
        export SDKROOT="$FALLBACK_SDK"
        echo "SDK: $SDKROOT"
    fi
fi

swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

APP="build/Macdow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Macdow" "$APP/Contents/MacOS/Macdow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -d Resources/WineOverrides ]]; then
    cp -R Resources/WineOverrides "$APP/Contents/Resources/WineOverrides"
fi
codesign --force --sign - "$APP" >/dev/null

echo "완료: $(pwd)/$APP"
echo "실행: open \"$APP\"  (응용 프로그램 폴더로 옮겨 사용해도 됩니다)"
