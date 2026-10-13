#!/bin/bash
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MELLOW_ROOT"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo 'iOS SDK가 없습니다. Xcode 전체 버전과 iOS 플랫폼을 설치한 뒤 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer 로 실행하세요.' >&2
  exit 2
fi
MELLOW_MODE="${1:-simulator}"
MELLOW_ARGS=(-project iOS/MellowPhoto.xcodeproj -scheme MellowPhotoIOS -derivedDataPath .build/ios)
case "$MELLOW_MODE" in
  simulator) xcodebuild "${MELLOW_ARGS[@]}" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build ;;
  test)
    : "${MELLOW_SIMULATOR_ID:?xcrun simctl list devices available 로 확인한 iPhone UUID를 MELLOW_SIMULATOR_ID에 지정하세요.}"
    xcodebuild "${MELLOW_ARGS[@]}" -destination "platform=iOS Simulator,id=$MELLOW_SIMULATOR_ID,arch=$(uname -m)" CODE_SIGNING_ALLOWED=NO test ;;
  device) xcodebuild "${MELLOW_ARGS[@]}" -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build ;;
  archive)
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID를 지정하세요.}"
    xcodebuild "${MELLOW_ARGS[@]}" -configuration Release -destination 'generic/platform=iOS' -archivePath .build/MellowPhotoIOS.xcarchive "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" archive ;;
  *) echo 'Usage: scripts/build-ios.sh [simulator|test|device|archive]' >&2; exit 2 ;;
esac
