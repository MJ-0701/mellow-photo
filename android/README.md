# Android (예정)

Kotlin 네이티브 앱. 아직 코드가 없다. 시작할 때 지킬 것:

- 모듈은 `docs/architecture/modules.md`의 다섯 모듈과 1:1 (`:shared`, `:editing`, `:library`, `:rendering`, `:export`).
- 레시피·세션 파일은 `shared/recipe-schema/`의 스키마를 그대로 읽고 쓴다. `shared/fixtures/`로 호환을 테스트한다.
- 편집 규칙은 `apple/Sources/MellowEditing/API/EditDocument.swift`가 기준 구현이다. 테스트 케이스 이름을 맞춘다.
- 배포 태그는 `android-vX.Y.Z` (`scripts/release.sh android X.Y.Z`).
