#!/bin/bash
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
bash scripts/verify-modules.sh
(cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests)
(cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj) || { echo 'project.yml과 xcodeproj가 다릅니다. xcodegen generate 결과를 커밋하세요.' >&2; exit 1; }
(cd apple && swift test)
IPHONE="$(mellow_first_simulator iPhone)"
IPAD="$(mellow_first_simulator iPad)"
for destination in "platform=iOS Simulator,id=$IPHONE" "platform=iOS Simulator,id=$IPAD" "platform=macOS"; do
  echo "== app tests: $destination"
  xcodebuild "${MELLOW_PROJECT[@]}" -destination "$destination" CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
done
