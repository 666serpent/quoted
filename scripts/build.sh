#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_BUILD_DIR="${QUOTED_BUILD_DIR:-$QUOTED_ROOT/.build}"
QUOTED_OUTPUT_DIR="${QUOTED_OUTPUT_DIR:-$QUOTED_ROOT/dist}"
export CLANG_MODULE_CACHE_PATH="$QUOTED_BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$QUOTED_BUILD_DIR/module-cache"
mkdir -p "$QUOTED_BUILD_DIR/module-cache" "$QUOTED_OUTPUT_DIR"
swift build --disable-sandbox --package-path "$QUOTED_ROOT" --scratch-path "$QUOTED_BUILD_DIR" \
    --cache-path "$QUOTED_BUILD_DIR/spm-cache" --config-path "$QUOTED_BUILD_DIR/spm-config" \
    --security-path "$QUOTED_BUILD_DIR/spm-security" -c release
QUOTED_BIN_DIR="$(swift build --disable-sandbox --package-path "$QUOTED_ROOT" --scratch-path "$QUOTED_BUILD_DIR" --cache-path "$QUOTED_BUILD_DIR/spm-cache" --config-path "$QUOTED_BUILD_DIR/spm-config" --security-path "$QUOTED_BUILD_DIR/spm-security" --show-bin-path -c release)"
QUOTED_APP="$QUOTED_OUTPUT_DIR/Quoted.app"
mkdir -p "$QUOTED_APP/Contents/MacOS" "$QUOTED_APP/Contents/Resources"
cp "$QUOTED_BIN_DIR/Quoted" "$QUOTED_APP/Contents/MacOS/Quoted"
cp "$QUOTED_ROOT/Resources/Info.plist" "$QUOTED_APP/Contents/Info.plist"
if [ -f "$QUOTED_ROOT/Resources/AppIcon.icns" ]; then
    cp "$QUOTED_ROOT/Resources/AppIcon.icns" "$QUOTED_APP/Contents/Resources/AppIcon.icns"
fi
cp "$QUOTED_ROOT/Resources/Assets.car" "$QUOTED_APP/Contents/Resources/Assets.car"
rm -f "$QUOTED_APP/Contents/Resources/AppIconDark.icns"
codesign --force --sign - --options runtime --entitlements "$QUOTED_ROOT/Resources/Quoted.entitlements" "$QUOTED_APP"
printf 'Built %s\n' "$QUOTED_APP"
