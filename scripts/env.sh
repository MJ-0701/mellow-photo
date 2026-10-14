#!/bin/bash
# 모든 Apple 스크립트가 source한다. Command Line Tools에는 XCTest와 iOS SDK가 없다.
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MELLOW_ROOT
if [[ -z "${DEVELOPER_DIR:-}" || "$DEVELOPER_DIR" == *CommandLineTools* ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo 'Xcode가 필요합니다. /Applications/Xcode.app을 설치하거나 DEVELOPER_DIR을 지정하세요.' >&2
    exit 2
  fi
fi
MELLOW_PROJECT=(-project "$MELLOW_ROOT/apple/MellowPhoto.xcodeproj" -scheme MellowPhoto -derivedDataPath "$MELLOW_ROOT/apple/build")
export MELLOW_PROJECT
mellow_first_simulator() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
prefix = sys.argv[1]
for runtime, items in devices.items():
    if 'iOS' not in runtime: continue
    for item in items:
        if item['name'].startswith(prefix) and item['isAvailable']:
            print(item['udid']); sys.exit(0)
sys.exit('no simulator starting with ' + prefix)
" "$1"
}
