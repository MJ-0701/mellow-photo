#!/bin/bash
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
bash scripts/build-apple.sh mac
APP="$MELLOW_ROOT/apple/build/Build/Products/Release/Mellow Photo.app"
mkdir -p dist
STAGE="$(mktemp -d "$MELLOW_ROOT/dist/mac-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Mellow Photo.app"
cp docs/MAC_INSTALL.md "$STAGE/설치와 사용 안내.txt"
ditto -c -k --sequesterRsrc "$STAGE" dist/Mellow-Photo-Mac.zip
(cd dist && shasum -a 256 Mellow-Photo-Mac.zip > Mellow-Photo-Mac.zip.sha256)
echo "Package: dist/Mellow-Photo-Mac.zip (임시 서명, 공증 전)"
