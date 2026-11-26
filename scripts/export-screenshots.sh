#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_DOCS_DIR="${QUOTED_DOCS_DIR:-$QUOTED_ROOT/.build-docs}"
export QUOTED_DOCS_DIR
"$QUOTED_ROOT/scripts/prepare-screenshots.sh"
mkdir -p "$QUOTED_ROOT/docs/images"
for QUOTED_VARIANT in dark light credits; do
    QUOTED_IMAGE="reading-$QUOTED_VARIANT.png"
    if [ "$QUOTED_VARIANT" = credits ]; then QUOTED_IMAGE="credits.png"; fi
    "$QUOTED_DOCS_DIR/Quoted-$QUOTED_VARIANT.app/Contents/MacOS/Quoted" \
        --export-documentation "$QUOTED_ROOT/docs/images/$QUOTED_IMAGE"
done
