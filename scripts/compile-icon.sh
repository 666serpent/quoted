#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_ICON_BUILD_DIR="${QUOTED_ICON_BUILD_DIR:-$QUOTED_ROOT/.build-icon}"
if [ -z "${QUOTED_ACTOOL:-}" ]; then
    QUOTED_ACTOOL="$(xcrun --find actool 2>/dev/null)" || {
        printf 'Set QUOTED_ACTOOL to a compiler supporting Icon Composer .icon documents.\n' >&2
        exit 1
    }
fi
mkdir -p "$QUOTED_ICON_BUILD_DIR"
"$QUOTED_ACTOOL" "$QUOTED_ROOT/Resources/AppIcon.icon" \
    --compile "$QUOTED_ICON_BUILD_DIR" --app-icon AppIcon --include-all-app-icons \
    --output-partial-info-plist "$QUOTED_ICON_BUILD_DIR/icon-info.plist" \
    --target-device mac --minimum-deployment-target 26.0 --platform macosx
cp "$QUOTED_ICON_BUILD_DIR/Assets.car" "$QUOTED_ROOT/Resources/Assets.car"
if [ -f "$QUOTED_ICON_BUILD_DIR/AppIcon.icns" ]; then
    cp "$QUOTED_ICON_BUILD_DIR/AppIcon.icns" "$QUOTED_ROOT/Resources/AppIcon.icns"
fi
