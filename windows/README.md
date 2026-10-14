# Windows (예정)

C/C++ 네이티브 앱. 아직 코드가 없다. 시작할 때 지킬 것:

- 모듈은 `docs/architecture/modules.md`의 다섯 모듈과 1:1인 CMake 타깃 (`mellow_shared`, `mellow_editing`, `mellow_library`, `mellow_rendering`, `mellow_export`). 의존 방향도 같은 표를 따른다.
- 레시피·세션 파일은 `shared/recipe-schema/`의 스키마를 그대로 읽고 쓴다. `shared/fixtures/`로 호환을 테스트한다.
- 편집 규칙은 `apple/Sources/MellowEditing/API/EditDocument.swift`가 기준 구현이다. 테스트 케이스 이름을 맞춘다.
- 배포 태그는 `windows-vX.Y.Z` (`scripts/release.sh windows X.Y.Z`).
