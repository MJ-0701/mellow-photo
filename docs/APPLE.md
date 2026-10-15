# Apple 앱 (iPhone·iPad·Mac)

SwiftUI 멀티플랫폼 앱 하나가 iPhone·iPad(iOS 17 이상)와 Mac(macOS 14 이상)을 모두 지원합니다. 번들 ID는 세 기기 모두 `com.mj.mellowphoto`입니다. 보정 엔진과 편집 규칙은 `apple/Sources/`의 Swift 모듈 다섯 개에 있고, 앱 타깃(`apple/MellowPhoto/`)은 화면과 플랫폼 어댑터만 담습니다. 구조는 [모듈 캔버스](architecture/modules.md)를 참조하세요.

## 준비 및 실행

1. Xcode 전체 버전과 iOS 플랫폼/시뮬레이터를 설치합니다. Command Line Tools만으로는 앱과 XCTest를 빌드할 수 없습니다. 현재 App Store 제출에는 Xcode 26 / iOS 26 SDK 이상이 필요합니다.
2. XcodeGen을 설치합니다: `brew install xcodegen`. 버전은 `apple/.xcodegen-version`(현재 2.46.0)에 고정되어 있고, `scripts/test-apple.sh`는 다른 버전이 설치되어 있으면 멈춥니다. 앱 타깃의 진실의 원천은 `apple/project.yml`이며, 이 파일을 고치면 `apple/`에서 `xcodegen generate`를 실행하고 생성된 `apple/MellowPhoto.xcodeproj`를 함께 커밋합니다.
3. `apple/MellowPhoto.xcodeproj`를 열고 **MellowPhoto** 스킴을 선택한 뒤 iPhone·iPad 시뮬레이터 또는 My Mac을 골라 실행합니다. 실제 iPhone·iPad는 Signing & Capabilities에서 본인 Team을 고른 뒤 연결합니다.

명령줄에서는 다음 스크립트를 씁니다. 모두 `scripts/env.sh`를 읽어 `DEVELOPER_DIR`이 Command Line Tools면 `/Applications/Xcode.app`으로 바꿉니다.

```sh
./scripts/build-apple.sh ios-simulator   # 서명 없는 Release 시뮬레이터 빌드
./scripts/build-apple.sh ios-device      # 서명 없는 Release iPhone·iPad 빌드 + 번들 ID·arm64·에셋·개인정보 manifest 검사
./scripts/build-apple.sh mac             # Release Mac 빌드(arm64·x86_64) + 서명 검사
open apple/build/Build/Products/Release/Mellow\ Photo.app
./scripts/package-mac.sh                 # dist/Mellow-Photo-Mac.zip (임시 서명, 공증 전)
./scripts/test-apple.sh                  # 모듈 검사·포맷·XcodeGen 동기화·패키지 테스트·Mac 앱 테스트 (CI는 iPhone·iPad도)
MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh   # 로컬에서 iPhone·iPad 시뮬레이터 앱 테스트까지
```

환경 변수 `MELLOW_BUILD_NUMBER`를 주면 `build-apple.sh`가 `CURRENT_PROJECT_VERSION`(CFBundleVersion)을 그 값으로 덮어씁니다. 릴리스 워크플로가 씁니다. `scripts/tools/make-icon.swift`와 `make-ios-icon.swift`는 앱 아이콘 PNG를 다시 만들 때만 씁니다. 생성된 아이콘은 에셋에 커밋되어 있습니다.

## 사용

공통:

- 도구 줄은 **필터 · 자동 · 자르기 · 조정 · 뷰티 · 메이크업 · 체형 · 배경 · 잡티 · 변형** 순서이고 가로로 스크롤됩니다. *자동*은 도구가 아니라 누르는 즉시 적용하는 버튼입니다.
- 필터: 원본 칩과 룩 10종(맑음·필름·포근·차분·모노·세피아·빈티지·선명·파스텔·밤) 칩. 칩 썸네일은 필터 도구를 처음 열 때 만들며 그동안 스피너가 돌아갑니다. 필터를 고르면 *강도* 슬라이더가 나옵니다. 같은 칩을 다시 누르면 해제합니다.
- 자동: 노출·하이라이트·그림자·따뜻함·채도·대비를 채웁니다. 얼굴이 있으면 피부 보정 0.3·자동 잡티·눈 또렷하게 0.2를 켭니다. 얼굴형·체형·메이크업은 건드리지 않습니다. 필터와 자르기도 건드리지 않습니다. 실행 취소 한 번으로 되돌립니다.
- 자르기: 이 도구에서는 캔버스가 자르기 전 사진(반전·회전·수평 보정만 적용)을 보여 주고, 바깥을 어둡게 한 자르기 사각형에 손잡이 8개가 붙습니다. 모서리·변을 끌면 크기, 안쪽을 끌면 위치가 바뀝니다. 비율 버튼(원본·1:1·4:5·3:4·9:16)은 사진 안 가장 큰 중앙 사각형을 만들고, 비율을 고른 동안에는 손잡이를 끌어도 비율을 지킵니다. *원본*은 자르기를 없앱니다. *90° 회전*과 화면 기준 *좌우 반전*은 자르기 사각형도 사진과 함께 옮깁니다. 회전하면 4:5·3:4·9:16 선택은 풀리고 1:1·원본은 남습니다. *수평* 슬라이더는 ±15°이고 빈 모서리가 생기지 않게 확대합니다. *되돌리기*는 자르기·회전·반전·수평만 처음으로 돌립니다. 이 도구에서는 잡티·변형 탭을 받지 않습니다.
- 조정: 분위기 프리셋(내추럴·포근한·클린), 노출·대비·채도·따뜻함, 하이라이트·그림자·선명도·비네팅. 슬라이더 값(뷰티 값 포함, 필터·자르기 제외)은 프리셋으로 저장해 다시 쓸 수 있습니다.
- 뷰티: 얼굴 선택 아래 *피부*·*얼굴*·*눈·입* 탭. 피부 탭은 *피부 보정*(모공 대역은 남기고 얼룩 대역만 줄임)과 *자동 잡티*(사진을 준비할 때 얼굴당 최대 40개를 찾아 수동 잡티와 같은 방식으로 지움). 얼굴 탭은 *얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이* 10개이고 미소를 뺀 9개는 가운데 0인 양방향(0 근처에서 붙음)입니다. 얼굴형 변형은 모두 한 번에 다시 그립니다. 고개를 많이 돌린 얼굴은 약하게 적용됩니다. 수동 잡티·변형이 있으면 얼굴형 슬라이더와 얼굴 선택이 잠깁니다. 눈·입 탭은 *눈 또렷하게*(흰자를 밝히고 홍채를 선명하게)·*치아 미백*(입을 벌린 사진에서만)·*입술 생기* 0…1이고 수동 편집이 있어도 잠기지 않습니다. 대상 얼굴에 특징점이 없으면 얼굴형·눈·입·메이크업이 바뀌지 않는다는 안내가 보입니다.
- 메이크업: 룩 칩(*없음*·데일리·쿨톤·웜피치·로지·스모키) 아래 *립·블러셔·아이섀도·눈썹·쉐딩* 탭. 립·블러셔·아이섀도는 색 칩(같은 칩을 다시 누르면 색을 뺌, 처음 고르면 강도 0.5)과 *강도*, 눈썹·쉐딩은 *강도*만. 룩을 고르면 다섯 부위 값을 한 번에 채우고(실행 취소 한 번), 부위를 바꾸면 룩 선택이 풀립니다. 색만 바꾸므로 수동 잡티·변형이 있어도 잠기지 않습니다. 특징점이 없는 얼굴이면 뷰티와 같은 안내가 보이고, 메이크업 목록 파일을 읽지 못하면 안내를 보입니다.
- 체형: *다리 길게*(0…1)·*허리·몸 전체·팔·허벅지·어깨·목*(가운데 0인 양방향, 0 근처에서 붙음). 사진을 준비할 때 찾은 관절점으로 가장 큰 사람 한 명만 바꾸고 얼굴형과 함께 한 번에 다시 그립니다. 두 어깨를 찾지 못했거나 체형 분석이 실패하면 안내를 보이고 슬라이더를 끕니다(프리셋으로 들어온 0이 아닌 값은 되돌릴 수 있게 켭니다). 수동 잡티·변형이 있으면 잠깁니다.
- 배경: *배경 흐림* 0…1. 사진을 준비할 때 찾은 인물 영역 밖만 흐립니다. 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더를 끕니다(프리셋으로 들어온 0이 아닌 값은 되돌릴 수 있게 켭니다).
- 자른 사진에서도 잡티·변형 위치는 원본 기준으로 기록합니다. 그래서 나중에 자르기를 바꿔도 보정 위치가 어긋나지 않습니다.
- 얼굴형·체형을 먼저 조정한 뒤 잡티나 부분 변형을 사용하세요. 수동 작업이 있으면 얼굴형·체형·대상 선택은 좌표 보호를 위해 잠깁니다.
- 잡티: 깨끗한 부분을 샘플로 한 번 누른 뒤 보정할 부분을 누릅니다. 변형: 필요한 부분을 조금 드래그합니다. 핀치(Mac은 트랙패드)로 화면을 100~400% 확대하고, iPad·Mac은 −/+ 버튼도 쓸 수 있습니다.
- 실행 취소·다시 실행은 사진마다 최대 40단계입니다.
- 기본 출력은 긴 변 최대 4096px, 8bit sRGB SDR JPEG입니다. PNG도 고를 수 있습니다. *원본 해상도*를 켜면 크기 제한 없이 저장하며 메모리 사용량이 크게 늘 수 있습니다. HDR·ProRAW·Live Photo 영상 보존은 지원하지 않습니다.
- ‘편집에서 사진 빼기’는 앱 내부 사본만 삭제합니다. 사진 앱이나 사용자 폴더의 원본은 변경하거나 삭제하지 않습니다.
- 앱을 백그라운드로 보내면 일괄 저장은 현재 사진까지만 마치고 멈춥니다.

| | iPhone·iPad | Mac |
|---|---|---|
| 가져오기 | 사진 앱(PhotosPicker), 파일 선택. 드래그 앤 드롭 처리(`.onDrop`) 코드는 있으나 iPad·iPhone에서 동작은 미검증 | 사진 앱(PhotosPicker), 파일 선택, 드래그 앤 드롭 |
| 저장 | 사진 앱에 새 사진으로 추가. 최초 저장 때 사진 추가 권한 요청 | 폴더를 고르면 `<이름>_mellow.<확장자>`로 저장, 같은 이름이 있으면 `_2`, `_3`…을 붙임. 1장 이상 저장되면 Finder로 폴더를 엶 |
| 복제 샘플 바꾸기 | *샘플 위치 다시 고르기* 버튼 | 버튼 또는 Option+클릭 |
| 화면 | iPhone 세로는 상단 사진 띠·캔버스·실행 취소 바·하단 도구 줄과 도구 패널, iPad는 라이브러리·캔버스·인스펙터 3단(도구 줄은 인스펙터 맨 위) | 라이브러리·캔버스·인스펙터 3단(도구 줄은 인스펙터 맨 위) |
| 키보드 | 하드웨어 키보드에서 ⌘O·⌘Z·⇧⌘Z·⇧⌘S | ⌘O 가져오기, ⌘Z 실행 취소, ⇧⌘Z 다시 실행, ⇧⌘S 현재 사진 저장 |

iCloud에만 있는 원본은 가져오는 동안 네트워크가 필요할 수 있습니다. 보정은 기기 내부에서 처리합니다. 사진 앱에 저장을 다시 누르면 새 사본이 추가되므로 중복 저장에 주의하세요.

## 기기별 한도

| 항목 | 기준 |
|---|---|
| 한 번에 편집할 사진 수 | 물리 메모리 4GB 미만 12장, 8GB 미만 24장, 그 이상 40장 |
| 미리보기 긴 변 | 메모리 8GB 이상 1600px, 미만 1200px |
| 저장 긴 변 | 기본 4096px, *원본 해상도*를 켜면 제한 없음 |

## 작업 사본과 편집 기록

- 가져온 사진은 `Application Support/MellowPhoto/Library/<uuid>.<확장자>`에 작업 사본으로 복사합니다. 작업 폴더는 기기 백업에서 제외하고, iOS에서는 파일 보호를 겁니다. 출시된 iPhone 앱(v1)이 `MellowPhoto/` 바로 아래에 두었던 사본도 그대로 찾습니다.
- 사진 목록, 보정값, 실행 취소·다시 실행 기록, 프리셋은 `Application Support/MellowPhoto/session.json`에 저장합니다. 형식은 v2이며 출시본 iPhone의 v1 파일도 읽어 이어서 편집합니다. 형식 계약은 [shared/recipe-schema](../shared/recipe-schema/README.md)에 있습니다. 읽을 수 없는 기록은 `session-recovery-<uuid>.json`으로 보존한 뒤 새로 시작합니다.
- iPhone·iPad·Mac 모두 앱을 다시 열면 지난 작업을 복원합니다. 기기 사이에 편집 기록을 동기화하지는 않습니다.
- 앱을 삭제하면 작업 사본과 기록이 사라지므로 완성한 사진은 먼저 저장하세요.

### Mac 샌드박스와 이전 버전 데이터

Mac 앱은 App Sandbox(사용자가 고른 파일 읽기·쓰기)에서 실행됩니다. 위 경로는 실제로 앱 컨테이너 안(`~/Library/Containers/com.mj.mellowphoto/Data/Library/Application Support/MellowPhoto`)에 있습니다.

- 첫 실행 때 `apple/MellowPhoto/Resources/container-migration.plist`에 따라 macOS가 샌드박스 밖의 이전 폴더 `~/Library/Application Support/MellowPhoto`를 컨테이너로 옮깁니다.
- 이전 Mac 앱이 남긴 `presets.json`은 세션을 복원한 뒤 세션 프리셋으로 가져오고 `presets.json.imported`로 이름을 바꿉니다. 다음 실행에서는 다시 읽지 않습니다.

## 검증 상태

2026-10-15 로컬 기준(`MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh`, 브랜치 `beauty-b-to-f` 커밋 `7d8ac3f`, 종료 코드 0): 패키지 `swift test` 331개(MellowShared 43 · MellowRendering 225 · MellowLibrary 30 · MellowExport 4 · MellowEditing 29), 앱 테스트 iPhone 시뮬레이터 67개 · iPad 시뮬레이터 67개 · Mac 68개 통과. 같은 커밋에서 `./scripts/build-apple.sh ios-device`와 `mac`도 종료 코드 0입니다. 로컬 `./scripts/test-apple.sh`는 `MELLOW_IOS_TESTS=1`이 없으면 iPhone·iPad 시뮬레이터 앱 테스트를 건너뜁니다(시뮬레이터 SpringBoard 오류 창 때문, CI는 항상 실행). 화면을 직접 보는 확인은 [VALIDATION.md](../VALIDATION.md)의 미검증 목록에 있습니다. CI(`.github/workflows/apple-checks.yml`)는 PR과 main push에서 `scripts/test-apple.sh`와 서명 없는 iPhone·Mac Release 빌드를 실행합니다.

기기에서 반드시 확인할 항목: 도구 줄 스크롤, 필터 칩 썸네일과 룩 10종의 실제 사진 결과, 자르기 손잡이 드래그(확대 상태 포함), 최초 권한 허용/거절, HEIC 및 방향 회전, iCloud 사진 가져오기, 얼굴 0/1/여러 명, 잡티·변형 후 실행 취소, 재실행 복원(출시본 v1 기록 포함), 전체 사진 저장, 48MP 메모리, 작은 화면과 큰 글자, 백그라운드 전환, 피부 보정·자동 잡티의 실제 사진 결과(주근깨, 머리카락 경계), 얼굴형 10종의 실제 사진 결과(과한 값, 기울어진 얼굴, 배경 직선 휨), 눈·치아·입술 보정의 실제 사진 결과(노란 조명, 다문 입·웃는 입), 배경 흐림의 인물 경계(머리카락·손가락·여러 사람)와 시뮬레이터·구형 기기의 인물 분석 실패 안내, 체형 7종의 실제 전신 사진 결과(과한 값, 팔이 몸에 붙은 자세, 여러 사람, 다리 높이 배경 직선 휨, 다리 길게의 아래쪽 잘림, 몸을 가늘게 할 때 흐린 배경이 안쪽으로 끌려옴)와 시뮬레이터·구형 기기의 체형 분석 실패 안내, 메이크업 5룩과 부위별 색의 실제 인물 사진 결과(어두운·밝은 입술, 앞머리·안경, 기울어진 얼굴, 여러 사람, 특징점을 못 찾은 얼굴 안내), Mac의 이전 폴더 이전과 프리셋 가져오기.

## TestFlight 배포

지금은 내부 테스터 두 명에게 TestFlight 빌드만 보내는 것이 기본입니다. 릴리스 워크플로(Actions 화면 이름 `Apple release`)는 배포 모드 두 가지를 지원합니다.

| 모드 | 하는 일 | App Store 버전 |
|---|---|---|
| `testflight` (기본) | 서명한 빌드를 TestFlight에 올리고 끝냅니다 | 만들지도 고치지도 않습니다 |
| `appstore` | 지금까지의 스토어 출시 경로입니다. 변경사항 반영, 설정에 따라 심사 제출까지 합니다 | 해당 버전을 만들거나 고칩니다 |

- 태그로 배포할 때 모드는 저장소 변수 `IOS_RELEASE_MODE`로 정합니다. 비워 두거나 `testflight`이면 TestFlight 전용, `appstore`이면 스토어 출시입니다. 다른 값이면 워크플로가 테스트 전에 멈춥니다.
- 수동 실행(Run workflow)에서는 입력 `mode`로 고르며 기본값은 `testflight`입니다.
- 태그 절차: `scripts/release.sh apple X.Y.Z`로 버전 커밋과 태그를 만든 뒤 `git push origin main apple-vX.Y.Z`로 올립니다.
- `appstore` 모드는 App Store Connect에 편집 가능한 다른 버전이 남아 있으면 빌드 전에 멈춥니다. 예전 편집 중 버전(예: 0.2.0)을 먼저 정리해야 합니다. `testflight` 모드는 이 조건과 상관없이 올라갑니다.
- `testflight` 모드는 Apple 처리가 끝날 때까지 기다린 뒤 두 그룹에 배포합니다. 내부 그룹 "Mellow Photo Internal"은 바로 받고, 외부 그룹 "Mellow Photo External"은 Apple 베타 심사를 통과하면 받습니다. 내부 그룹의 자동 배포 설정은 꺼져 있어도 됩니다.
- "테스트할 내용" 문구는 `fastlane/release_notes/<버전>.json`의 한국어 값을 씁니다. 파일이 없으면 기본 문구가 들어갑니다.
- 이미 올라간 빌드를 그룹에 배포만 하려면 Actions의 `Apple TestFlight distribute`를 버전·빌드 번호를 넣어 수동 실행합니다.
- `testflight` 모드는 2026-10-15 `apple-v0.3.1`, `apple-v1.1.0`으로 업로드까지 확인했습니다.
- 버전 번호는 이미 올린 가장 높은 버전(1.0.0)보다 커야 TestFlight에서 최신으로 보입니다.
- 업로드 뒤 Apple 쪽 처리 상태와 내부 그룹 설정은 Actions의 `Apple TestFlight status` 워크플로를 수동 실행해 확인합니다. 읽기만 하고 아무것도 바꾸지 않습니다.

App Store 자동화는 [IOS_RELEASE.md](IOS_RELEASE.md), 제출 자료는 [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md), Mac 전달본은 [MAC_INSTALL.md](MAC_INSTALL.md)를 참조하세요.

공개 지원: https://mj-0701.github.io/mellow-photo-support/
개인정보 안내: https://mj-0701.github.io/mellow-photo-support/privacy.html
