#!/bin/bash
# 사용법: scripts/release.sh apple 1.0.0  →  Version.xcconfig 갱신, 커밋, 태그 apple-v1.0.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
VERSION="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo '작업 트리가 깨끗해야 합니다.' >&2; exit 1; }
case "$PLATFORM" in
  apple)
    FILE="$ROOT/apple/Config/Version.xcconfig"
    sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" "$FILE"
    git -C "$ROOT" add "$FILE" ;;
  android|windows) echo "$PLATFORM 버전 파일은 아직 없습니다. 태그만 만듭니다." ;;
  *) echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2 ;;
esac
TAG="$PLATFORM-v$VERSION"
git -C "$ROOT" tag -l "$TAG" | grep -q . && { echo "태그 $TAG가 이미 있습니다." >&2; exit 1; }
git -C "$ROOT" commit -q -m "chore(release): $PLATFORM $VERSION" --allow-empty
git -C "$ROOT" tag -a "$TAG" -m "$PLATFORM $VERSION"
echo "태그 $TAG 생성. 푸시: git push origin main $TAG"
