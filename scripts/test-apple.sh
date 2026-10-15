#!/bin/bash
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
bash scripts/verify-modules.sh
(cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests)
PINNED_XCODEGEN="$(tr -d '[:space:]' < apple/.xcodegen-version)"
command -v xcodegen >/dev/null || { echo "xcodegen이 없습니다. $PINNED_XCODEGEN 버전을 설치하세요." >&2; exit 1; }
INSTALLED_XCODEGEN="$(xcodegen --version | sed -n 's/^Version: *//p')"
[[ "$INSTALLED_XCODEGEN" == "$PINNED_XCODEGEN" ]] || { echo "xcodegen ${INSTALLED_XCODEGEN}가 설치되어 있지만 저장소는 ${PINNED_XCODEGEN}을 기대합니다. 같은 버전을 설치하거나 apple/.xcodegen-version을 갱신하세요." >&2; exit 1; }
(cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj) || { echo 'project.yml과 xcodeproj가 다릅니다. xcodegen generate 결과를 커밋하세요.' >&2; exit 1; }
(cd apple && swift test)
IPHONE="$(mellow_first_simulator iPhone)"
IPAD="$(mellow_first_simulator iPad)"
# 시뮬레이터 병렬 테스트는 복제 기기를 켰다 지우면서 시뮬레이터 SpringBoard를 반복해서 죽인다. 기존 기기 하나로만 돌린다.
for destination in "platform=iOS Simulator,id=$IPHONE" "platform=iOS Simulator,id=$IPAD" "platform=macOS"; do
  echo "== app tests: $destination"
  parallel=()
  [[ "$destination" == *"iOS Simulator"* ]] && parallel=(-parallel-testing-enabled NO)
  # bash 3.2 + set -u는 빈 배열 전개를 오류로 본다.
  xcodebuild "${MELLOW_PROJECT[@]}" -destination "$destination" ${parallel[@]+"${parallel[@]}"} CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
done
