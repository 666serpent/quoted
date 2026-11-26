#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_OUTPUT_DIR="${QUOTED_OUTPUT_DIR:-$QUOTED_ROOT/dist}"
export QUOTED_OUTPUT_DIR
if [ "${QUOTED_SKIP_BUILD:-0}" != "1" ]; then
    "$QUOTED_ROOT/scripts/build.sh"
fi
QUOTED_APP="$QUOTED_OUTPUT_DIR/Quoted.app"
codesign --verify --deep --strict "$QUOTED_APP"
QUOTED_ARCH="$(uname -m)"
QUOTED_ARCHIVE="Quoted-macOS-$QUOTED_ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$QUOTED_APP" "$QUOTED_OUTPUT_DIR/$QUOTED_ARCHIVE"
(
    cd "$QUOTED_OUTPUT_DIR"
    shasum -a 256 "$QUOTED_ARCHIVE" > SHA256SUMS
)
printf 'Packaged %s\n' "$QUOTED_OUTPUT_DIR/$QUOTED_ARCHIVE"
