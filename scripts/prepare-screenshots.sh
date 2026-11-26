#!/bin/bash
set -euo pipefail
QUOTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUOTED_DOCS_DIR="${QUOTED_DOCS_DIR:-$QUOTED_ROOT/.build-docs}"
QUOTED_DOCS_APP="${QUOTED_DOCS_APP:-$QUOTED_ROOT/dist/Quoted.app}"
mkdir -p "$QUOTED_DOCS_DIR"
for QUOTED_VARIANT in dark light credits; do
    QUOTED_COPY="$QUOTED_DOCS_DIR/Quoted-$QUOTED_VARIANT.app"
    ditto "$QUOTED_DOCS_APP" "$QUOTED_COPY"
    python3 - "$QUOTED_COPY/Contents/Info.plist" "$QUOTED_VARIANT" <<'PY'
import plistlib, sys
from pathlib import Path
p=Path(sys.argv[1]); variant=sys.argv[2]
info=plistlib.loads(p.read_bytes())
info['CFBundleIdentifier']='app.quoted.documentation.'+variant
info['QuotedDocumentationAppearance']='light' if variant=='light' else 'dark'
info['QuotedDocumentationShowCredits']=variant=='credits'
p.write_bytes(plistlib.dumps(info))
PY
    codesign --force --sign - --options runtime --entitlements "$QUOTED_ROOT/Resources/Quoted.entitlements" "$QUOTED_COPY"
done
printf 'Prepared offline screenshot apps in %s\n' "$QUOTED_DOCS_DIR"
