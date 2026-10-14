#!/bin/bash
# 사용법: scripts/release.sh apple 1.0.0  →  Version.xcconfig 갱신, 커밋, 태그 apple-v1.0.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
VERSION="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo '작업 트리가 깨끗해야 합니다.' >&2; exit 1; }
TAG="$PLATFORM-v$VERSION"
# 파일을 고치기 전에 확인해 실패해도 작업 트리가 깨끗하게 남는다.
if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "태그 $TAG가 이미 있습니다." >&2
  exit 1
fi
FILE=""
COMMITTED=0
# 커밋 전에 어떤 이유로든 끝나면 고친 버전 파일을 HEAD 상태로 되돌린다.
restore_version_file() {
  if [[ "$COMMITTED" -ne 1 && -n "$FILE" ]]; then
    git -C "$ROOT" checkout -q HEAD -- "$FILE" || true
  fi
}
trap restore_version_file EXIT
case "$PLATFORM" in
  apple)
    FILE="$ROOT/apple/Config/Version.xcconfig"
    sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" "$FILE"
    grep -qx "MARKETING_VERSION = $VERSION" "$FILE" || { echo "Version.xcconfig 갱신 실패" >&2; exit 1; }
    git -C "$ROOT" add "$FILE" ;;
  android|windows) echo "$PLATFORM 버전 파일은 아직 없습니다. 태그만 만듭니다." ;;
  *) echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2 ;;
esac
if ! git -C "$ROOT" commit -q -m "chore(release): $PLATFORM $VERSION" --allow-empty; then
  echo '릴리스 커밋에 실패해 버전 파일 변경을 되돌렸습니다.' >&2
  exit 1
fi
COMMITTED=1
git -C "$ROOT" tag -a "$TAG" -m "$PLATFORM $VERSION"
echo "태그 $TAG 생성. 푸시: git push origin main $TAG"
