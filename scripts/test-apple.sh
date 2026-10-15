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
# iOS 26 시뮬레이터는 부팅 직후 SpringBoard가 배경화면 스냅샷 중 죽어 Mac에 오류 창이 뜬다(Apple 버그).
# 로컬에서는 iOS 시뮬레이터 테스트를 MELLOW_IOS_TESTS=1일 때만 돌리고, CI는 항상 돌린다.
destinations=()
if [[ -n "${CI:-}" || "${MELLOW_IOS_TESTS:-0}" == "1" ]]; then
  IPHONE="$(mellow_first_simulator iPhone)"
  IPAD="$(mellow_first_simulator iPad)"
  destinations+=("platform=iOS Simulator,id=$IPHONE" "platform=iOS Simulator,id=$IPAD")
else
  echo "== iOS 시뮬레이터 앱 테스트 생략 (MELLOW_IOS_TESTS=1로 실행하면 포함)"
fi
destinations+=("platform=macOS")
# 병렬 복제 기기를 만들지 않고 기존 기기 하나로 돌린다.
for destination in "${destinations[@]}"; do
  echo "== app tests: $destination"
  parallel=()
  [[ "$destination" == *"iOS Simulator"* ]] && parallel=(-parallel-testing-enabled NO)
  # bash 3.2 + set -u는 빈 배열 전개를 오류로 본다.
  xcodebuild "${MELLOW_PROJECT[@]}" -destination "$destination" ${parallel[@]+"${parallel[@]}"} CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
done
