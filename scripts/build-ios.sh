#!/bin/bash
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MELLOW_ROOT"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo 'iOS SDK가 없습니다. Xcode 전체 버전과 iOS 플랫폼을 설치한 뒤 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer 로 실행하세요.' >&2
  exit 2
fi
MELLOW_MODE="${1:-simulator}"
mkdir -p "$MELLOW_ROOT/.build"
MELLOW_ARGS=(-project iOS/MellowPhoto.xcodeproj -scheme MellowPhotoIOS -derivedDataPath .build/ios)
case "$MELLOW_MODE" in
  simulator) xcodebuild "${MELLOW_ARGS[@]}" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build ;;
  test)
    : "${MELLOW_SIMULATOR_ID:?xcrun simctl list devices available 로 확인한 iPhone UUID를 MELLOW_SIMULATOR_ID에 지정하세요.}"
    # Xcode refuses to overwrite an existing xcresult. Keep results from earlier runs.
    MELLOW_RESULT_DIR="$(mktemp -d "$MELLOW_ROOT/.build/ios-tests.XXXXXX")"
    echo "Test results: $MELLOW_RESULT_DIR/Tests.xcresult"
    xcodebuild "${MELLOW_ARGS[@]}" -resultBundlePath "$MELLOW_RESULT_DIR/Tests.xcresult" -destination "platform=iOS Simulator,id=$MELLOW_SIMULATOR_ID,arch=$(uname -m)" CODE_SIGNING_ALLOWED=NO test ;;
  device)
    xcodebuild "${MELLOW_ARGS[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
    # Verify the optimized arm64 device product, not only simulator compilation.
    MELLOW_APP="$MELLOW_ROOT/.build/ios/Build/Products/Release-iphoneos/MellowPhotoIOS.app"
    /usr/bin/plutil -lint "$MELLOW_APP/Info.plist" "$MELLOW_APP/PrivacyInfo.xcprivacy"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$MELLOW_APP/Info.plist")" == com.mj.mellowphoto ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$MELLOW_APP/Info.plist")" == iPhoneOS ]]
    MELLOW_ARCHS="$(/usr/bin/lipo -archs "$MELLOW_APP/MellowPhotoIOS")"
    case " $MELLOW_ARCHS " in
      *" arm64 "*) ;;
      *) echo "Expected arm64 device executable, got: $MELLOW_ARCHS" >&2; exit 1 ;;
    esac
    test -s "$MELLOW_APP/Assets.car"
    echo 'Unsigned Release iPhone arm64 app, assets and privacy manifest verified.' ;;

  archive)
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID를 지정하세요.}"
    xcodebuild "${MELLOW_ARGS[@]}" -configuration Release -destination 'generic/platform=iOS' -archivePath .build/MellowPhotoIOS.xcarchive "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" archive ;;
  *) echo 'Usage: scripts/build-ios.sh [simulator|test|device|archive]' >&2; exit 2 ;;
esac
