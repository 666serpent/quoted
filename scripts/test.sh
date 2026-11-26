#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_TEST_BUILD_DIR="${QUOTED_TEST_BUILD_DIR:-$QUOTED_ROOT/.build-tests}"
QUOTED_DEVELOPER_DIR="$(xcode-select -p)"
QUOTED_SWIFT_BIN="$(dirname "$(xcrun --find swiftc)")"
export CLANG_MODULE_CACHE_PATH="$QUOTED_TEST_BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$QUOTED_TEST_BUILD_DIR/module-cache"
QUOTED_FLAGS=(--disable-sandbox --disable-xctest --enable-swift-testing
    --package-path "$QUOTED_ROOT" --scratch-path "$QUOTED_TEST_BUILD_DIR"
    --cache-path "$QUOTED_TEST_BUILD_DIR/spm-cache" --config-path "$QUOTED_TEST_BUILD_DIR/spm-config"
    --security-path "$QUOTED_TEST_BUILD_DIR/spm-security")
# Command Line Tools include Swift Testing, but their Swift Build engine can
# omit its macro plugin. The native engine accepts the explicit plugin path.
QUOTED_TEST_FRAMEWORKS="$QUOTED_DEVELOPER_DIR/Library/Developer/Frameworks"
QUOTED_TEST_PLUGINS="$QUOTED_SWIFT_BIN/../lib/swift/host/plugins/testing"
if [[ "$QUOTED_DEVELOPER_DIR" == */CommandLineTools ]] && [[ -d "$QUOTED_TEST_FRAMEWORKS/Testing.framework" ]]; then
    QUOTED_FLAGS+=(--build-system native -Xswiftc -F -Xswiftc "$QUOTED_TEST_FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$QUOTED_TEST_FRAMEWORKS"
        -Xswiftc -external-plugin-path -Xswiftc "$QUOTED_TEST_PLUGINS#$QUOTED_SWIFT_BIN/swift-plugin-server")
fi
swift test "${QUOTED_FLAGS[@]}" "$@"
