#!/bin/bash
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MELLOW_ROOT"
swift build -c release
MELLOW_BIN="$(swift build -c release --show-bin-path)"
MELLOW_APP="$MELLOW_ROOT/dist/Mellow Photo.app"
mkdir -p "$MELLOW_APP/Contents/MacOS" "$MELLOW_APP/Contents/Resources"
cp "$MELLOW_BIN/MellowPhoto" "$MELLOW_APP/Contents/MacOS/MellowPhoto"
python3 - "$MELLOW_APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump({
        'CFBundleName':'Mellow Photo', 'CFBundleDisplayName':'Mellow Photo',
        'CFBundleIdentifier':'com.mj.mellowphoto', 'CFBundleExecutable':'MellowPhoto',
        'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.0',
        'CFBundleVersion':'1','LSMinimumSystemVersion':'14.0',
        'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication',
        'CFBundleIconFile':'AppIcon','LSApplicationCategoryType':'public.app-category.photography'
    },f)
PY
swift scripts/make-icon.swift "$MELLOW_ROOT/dist/icon.png"
mkdir -p "$MELLOW_ROOT/dist/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MELLOW_ROOT/dist/icon.png" --out "$MELLOW_ROOT/dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MELLOW_ROOT/dist/icon.png" --out "$MELLOW_ROOT/dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$MELLOW_ROOT/dist/AppIcon.iconset" -o "$MELLOW_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$MELLOW_APP"
echo "Built: $MELLOW_APP"
echo "Run: open \"$MELLOW_APP\""
