# Mellow Photo

인물·셀카 사진을 iPhone·iPad·Mac에서 보정하는 작은 로컬 사진 앱입니다. 사진이나 얼굴 데이터를 서버로 올리지 않으며, 가입과 API 키가 필요 없습니다.

## 저장소 구조

| 폴더 | 내용 |
|---|---|
| `apple/` | Apple 앱. Swift 패키지 MellowKit(모듈 5개, `apple/Package.swift`)와 iPhone·iPad·Mac 공통 SwiftUI 앱 타깃(`apple/MellowPhoto/`, 정의는 `apple/project.yml`) |
| `android/` | Android(Kotlin) 앱 자리. 아직 코드가 없습니다. [시작 규칙](android/README.md) |
| `windows/` | Windows(C/C++) 앱 자리. 아직 코드가 없습니다. [시작 규칙](windows/README.md) |
| `shared/` | 플랫폼 공통 계약. 레시피·세션 파일 JSON 스키마(`shared/recipe-schema/`), 필터 10종의 파라미터 데이터(`shared/looks/`), 호환 테스트용 픽스처(`shared/fixtures/`) |

그 밖에 `docs/`(안내·아키텍처 문서), `scripts/`(Apple 빌드·테스트·릴리스 스크립트), `fastlane/`(App Store 업로드), `.github/workflows/`(CI), `website/`(지원·개인정보 페이지)가 있습니다.

## 실행

Mac 앱을 직접 빌드하려면 macOS 14 이상과 Xcode 전체 버전이 필요합니다. 스크립트는 `DEVELOPER_DIR`이 Command Line Tools를 가리키면 `/Applications/Xcode.app`으로 바꿔 실행합니다. 외부 Swift 패키지 의존성은 없습니다.

```sh
./scripts/build-apple.sh mac
open apple/build/Build/Products/Release/Mellow\ Photo.app
```

Xcode에서는 `apple/MellowPhoto.xcodeproj`를 열고 **MellowPhoto** 스킴을 iPhone·iPad 시뮬레이터 또는 My Mac으로 실행합니다. 앱은 iOS 17·macOS 14 이상을 지원합니다. 다른 Mac으로 전달하는 zip은 `./scripts/package-mac.sh`로 만듭니다([Mac 설치와 사용 안내](docs/MAC_INSTALL.md)). iPhone·iPad·Mac 공통 안내는 [docs/APPLE.md](docs/APPLE.md)에 있습니다.

## 첫 보정

1. **사진 가져오기**에서 *사진 앱에서 고르기* 또는 *파일에서 고르기*로 HEIC·JPEG·PNG를 추가합니다. Mac과 iPad는 편집 화면으로 파일을 끌어다 놓아도 됩니다. 한 번에 편집할 수 있는 사진 수는 기기 메모리에 따라 12·24·40장입니다.
2. **필터**에서 맑음·필름·포근·차분·모노·세피아·빈티지·선명·파스텔·밤 중 하나를 고르고 *강도*를 조절합니다. 칩에는 선택한 사진에 필터를 입힌 썸네일이 보입니다. 같은 칩을 다시 누르거나 *원본* 칩을 누르면 필터를 뺍니다. 필터는 사진마다 따로 저장됩니다.
3. **자동**을 누르면 노출·하이라이트·그림자·따뜻함·채도·대비를 사진에 맞춰 채웁니다. 얼굴이 있으면 피부 정돈과 얼굴 미세 조정도 약하게 넣습니다. 실행 취소 한 번으로 되돌리고, 값이 그대로면 다시 눌러도 기록이 늘지 않습니다.
4. **자르기**에서 비율(원본·1:1·4:5·3:4·9:16)을 고르거나 모서리·변의 손잡이를 끌어 자를 부분을 정합니다. 사각형 안쪽을 끌면 위치를 옮깁니다. *90° 회전*, 화면 기준 *좌우 반전*, *수평*(±15°)도 있습니다. 회전·반전하면 자를 부분도 사진과 함께 움직입니다. *되돌리기*는 자르기·회전·반전·수평만 처음으로 돌립니다. 자르기 도구에서는 자르기 전 전체 사진이 보이고, 다른 도구로 가면 자른 결과가 보입니다.
5. **조정**에서 노출·대비·채도·따뜻함·하이라이트·그림자·선명도·비네팅을 다듬거나 내추럴·포근한·클린 프리셋을 고릅니다. 사용자 프리셋은 이 여덟 값과 인물 값(피부 정돈·얼굴 미세 조정)을 저장하며 필터와 자르기는 담지 않습니다.
6. **인물**에서 감지된 얼굴을 고르고 피부 정돈·얼굴 미세 조정을 사용합니다. 얼굴 번호는 화면 왼쪽부터입니다.
7. **잡티**에서 깨끗한 피부를 한 번 눌러 샘플을 고른 뒤 잡티를 누릅니다. 샘플 위치는 *샘플 위치 다시 고르기*로, Mac에서는 Option+클릭으로도 바꿉니다. 자른 사진에서 눌러도 위치는 원본 기준으로 기록됩니다.
8. **변형**에서 얼굴·체형의 일부를 조금 드래그해 조정합니다. 배경도 움직일 수 있으므로 원본과 비교하며 사용합니다.
9. **저장** 메뉴에서 형식(JPEG/PNG)과 원본 해상도 여부를 고르고 현재 사진 또는 전체 사진을 저장합니다. 자른 사진은 자른 크기로 저장됩니다. iPhone·iPad는 사진 앱에 새 사진으로 추가하고, Mac은 고른 폴더에 저장합니다.

도구 줄은 필터 · 자동 · 자르기 · 조정 · 인물 · 잡티 · 변형 순서입니다. iPhone 세로 화면은 아래쪽 도구 패널 위에, iPad·Mac은 인스펙터 맨 위에 있습니다.

수동 잡티 보정·부분 변형을 시작하면 얼굴 미세 조정과 얼굴 선택은 잠깁니다. 위치가 어긋나지 않도록 얼굴 형태부터 조정하세요. 실행 취소로 수동 작업을 모두 되돌리거나 초기화하면 다시 조정할 수 있습니다. 프리셋·전체 적용도 수동 작업이 있는 사진의 얼굴 형태는 유지합니다.

키보드: ⌘O 가져오기, ⌘Z 실행 취소, ⇧⌘Z 다시 실행, ⇧⌘S 현재 사진 저장.

## 구현된 범위와 한계

- ImageIO 기반 EXIF 방향 보정과 HEIC/JPEG/PNG 읽기
- Vision 얼굴 특징점과 눈·입 보호 영역을 이용한 얼굴 피부 필터
- 얼굴 양옆의 약한 국소 변형, 수동 드래그 변형
- 샘플 영역을 부드럽게 합성하는 수동 복제 브러시
- 필터 10종(`shared/looks/looks.v1.json`의 파라미터 데이터)과 강도 조절, 필터 칩 썸네일
- 자동 보정: 휘도 히스토그램과 평균색으로 슬라이더 값을 채우는 방식(얼굴이 있으면 피부 정돈 0.3·얼굴 미세 조정 0.15 포함), 실행 취소 한 번으로 되돌림
- 자르기(비율 5종과 자유 드래그), 90° 회전, 화면 기준 좌우 반전, 수평 보정 ±15°
- 색감 조정과 하이라이트·그림자·선명도·비네팅, 사용자 프리셋 저장, 전후 비교, 사진별 실행 취소·다시 실행(최대 40단계)
- 사진마다 인식한 얼굴 위치를 사용한 슬라이더 설정 일괄 적용
- 축소 미리보기와 원본 해상도 렌더, 기존 파일을 덮어쓰지 않는 저장
- 작업 사본과 편집 기록 저장. **Mac도 편집 기록을 복원합니다.** 앱을 다시 열면 iPhone·iPad·Mac 모두 사진 목록, 보정값, 실행 취소 기록, 프리셋을 이어서 씁니다.

피부 정돈은 마스크 기반 필터입니다. 학습 모델 기반 자동 잡티 탐지, Evoto와 동일한 보정 품질, 자동 전신 체형 인식은 구현하지 않았습니다. 얼굴을 찾지 못하면 얼굴 슬라이더를 쓸 수 없지만 색감과 수동 도구는 사용할 수 있습니다. 얼굴 분석에 실패한 사진은 얼굴 보정이 들어간 저장을 거부합니다. 미리보기는 긴 변 최대 1600픽셀(메모리 8GB 미만 기기는 1200픽셀)이라 저장 결과의 세부 질감(선명도 포함)은 다를 수 있습니다. 필터는 파라미터 조합이며 LUT(.cube) 필터, 사용자 필터 만들기, 필터 자동 추천, 텍스트·스티커는 없습니다. 자동 보정은 학습 모델이 아니라 밝기 분포 규칙입니다.

출력은 호환성을 위한 **8bit sRGB SDR JPEG/PNG**이고, 기본은 긴 변 최대 4096픽셀입니다. *원본 해상도*를 켜면 제한 없이 저장하지만 메모리를 많이 씁니다. HDR/gain map, Live Photo 영상, RAW/ProRAW 편집, 원본 색공간 그대로의 재출력은 지원하지 않습니다. 원본의 GPS·카메라 EXIF는 복사하지 않습니다. 원본 파일과 사진 앱의 원본은 변경하지 않습니다. 각 사진의 잡티 위치와 수동 변형은 다른 사진으로 복사하지 않습니다.

작업 사본과 기록은 앱의 `Application Support/MellowPhoto/`(`Library/` 폴더와 `session.json`)에 보관합니다. Mac 앱은 App Sandbox 안에서 실행되므로 실제 위치는 앱 컨테이너 안이며, 첫 실행 때 이전 Mac 앱의 `~/Library/Application Support/MellowPhoto` 폴더를 컨테이너로 옮기고 그 안의 `presets.json`을 세션 프리셋으로 가져온 뒤 `presets.json.imported`로 이름을 바꿉니다. 출시된 iPhone 앱의 기록(v1)도 그대로 이어서 엽니다. Evoto 코드·모델·프리셋·그래픽 자산은 이 저장소에 포함하지 않았으며 독립 구현입니다.

## 검증

```sh
./scripts/test-apple.sh
```

순서대로 모듈 의존성 검사(`scripts/verify-modules.sh`), `swift format lint --strict`, XcodeGen 프로젝트 동기화 확인, 패키지 테스트(`swift test`), iPhone·iPad 시뮬레이터와 Mac의 앱 테스트를 실행합니다. Xcode 전체 버전과 `apple/.xcodegen-version`에 고정된 XcodeGen(현재 2.46.0, `brew install xcodegen`)이 필요하며, 다른 버전이 설치되어 있으면 스크립트가 멈춥니다. 렌더링·내보내기 테스트는 Core Image GPU에 접근할 수 있는 macOS에서 실행해야 합니다.

`CIWarpKernel(source:)`는 기존 Core Image API라 현재 SDK에서 deprecation 경고가 발생합니다. 이 API는 `MellowRendering`의 `WarpKernel` 한 곳에서만 쓰므로, 지원이 제거되면 그 타입만 Metal 커널로 바꿉니다.

## 아키텍처

모듈 다섯 개(MellowShared · MellowEditing · MellowLibrary · MellowRendering · MellowExport)의 책임·공개 API·의존·포트는 [모듈 캔버스](docs/architecture/modules.md)에 있습니다. 파일 형식 계약은 [shared/recipe-schema](shared/recipe-schema/README.md)입니다.

이번 구조 정리(A) 다음 로드맵:

- **B 피부**: 피부 보정 고도화 (레시피 키 `skin`)
- **C 얼굴 리셰이프**: 얼굴 랜드마크 전체를 쓰는 형태 조정 (`reshape`)
- **D 디테일·배경**: 디테일과 배경 보정 (`detail`)
- **E 체형**: 체형 보정 (`body`)
- **F 메이크업**: 메이크업 효과 (`makeup`)

## 배포

```sh
./scripts/release.sh apple X.Y.Z
git push origin main apple-vX.Y.Z
```

`release.sh`가 `apple/Config/Version.xcconfig`의 `MARKETING_VERSION`을 고쳐 커밋하고 `apple-vX.Y.Z` 태그를 만듭니다. 태그를 push하면 `.github/workflows/apple-release.yml`이 테스트 → Mac zip 아티팩트 → iOS App Store 업로드를 진행합니다. 자세한 설정은 [App Store 출시와 자동 배포](docs/IOS_RELEASE.md)를 참조하세요.
