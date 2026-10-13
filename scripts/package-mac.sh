#!/bin/bash
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MELLOW_ROOT"
bash scripts/build-app.sh universal
MELLOW_APP="$MELLOW_ROOT/dist/Mellow Photo.app"
MELLOW_BINARY="$MELLOW_APP/Contents/MacOS/MellowPhoto"
MELLOW_ARCHS="$(lipo -archs "$MELLOW_BINARY")"
[[ " $MELLOW_ARCHS " == *" arm64 "* && " $MELLOW_ARCHS " == *" x86_64 "* ]]
MELLOW_STAGE="$(mktemp -d "$MELLOW_ROOT/dist/mac-package.XXXXXX")"
trap 'rm -rf "$MELLOW_STAGE"' EXIT
ditto "$MELLOW_APP" "$MELLOW_STAGE/Mellow Photo.app"
cp docs/MAC_INSTALL.md "$MELLOW_STAGE/설치와 사용 안내.txt"
MELLOW_ZIP="$MELLOW_ROOT/dist/Mellow-Photo-Mac.zip"
ditto -c -k --sequesterRsrc "$MELLOW_STAGE" "$MELLOW_ZIP"
(cd dist && shasum -a 256 Mellow-Photo-Mac.zip > Mellow-Photo-Mac.zip.sha256)
echo "Package: $MELLOW_ZIP"
echo 'Local ad-hoc signature only; Apple notarization is pending.'
