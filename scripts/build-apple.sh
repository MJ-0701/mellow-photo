#!/bin/bash
# 서명 없는 Release 빌드와 번들 검사.
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
MODE="${1:-ios-device}"
case "$MODE" in
  ios-simulator) xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet ;;
  ios-device)
    xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet
    APP="$MELLOW_ROOT/apple/build/Build/Products/Release-iphoneos/Mellow Photo.app"
    /usr/bin/plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" == com.mj.mellowphoto ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" == iPhoneOS ]]
    [[ " $(/usr/bin/lipo -archs "$APP/Mellow Photo") " == *" arm64 "* ]]
    test -s "$APP/Assets.car"
    echo 'Unsigned Release iPhone/iPad arm64 app, assets and privacy manifest verified.' ;;
  mac)
    xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build -quiet
    APP="$MELLOW_ROOT/apple/build/Build/Products/Release/Mellow Photo.app"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.mj.mellowphoto ]]
    ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Mellow Photo")"
    [[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]
    codesign --verify --deep --strict "$APP"
    echo "Built: $APP" ;;
  *) echo 'Usage: scripts/build-apple.sh [ios-simulator|ios-device|mac]' >&2; exit 2 ;;
esac
