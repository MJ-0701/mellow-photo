# v0.1 검증 기록

2026-10-13, Apple Silicon / macOS 26.6.2.

- Release 앱 빌드 및 임시 코드서명 성공.
- 독립 검수자가 실제 GPU 렌더링 테스트 7개 통과 확인.
- 편집 순서, 이미지 방향, 색온도 방향, 출력 크기, 동명 파일 보호 검증.
- 독립 StudioStore 실행 검사: 수동 편집 이후 얼굴 형태·대상 보호, 프리셋·일괄 적용 보호, 실행 취소·초기화 통과.
- 네이티브 화면에서 PNG 가져오기, 얼굴 1명 감지, 노출 변경 및 실행 취소, 피부 정돈, JPEG 저장 확인. 출력 크기 512×512 확인.
- 설치본 실행 확인. 이후 HEIC 가져오기 클릭 뒤 화면 자동화 연결 시간 초과로 설치본 HEIC 화면 검증은 완료하지 못함. 프로세스 샘플상 메인 스레드는 이벤트 대기 상태.

실제 iPhone 원본, HDR, 대용량 40장 부하, exFAT 저장 장치는 미검증. iOS 앱 빌드 및 TestFlight 배포는 이 버전에 포함하지 않음.

테스트 사진은 공개 도메인 NASA 우주비행사 이미지(scikit-image astronaut)를 임시 폴더에서만 사용했으며 저장소에는 포함하지 않음.

## iPhone 전환 작업

- 공유 엔진 iOS 16 지원 선언, 앱 최소 iOS 17. Mac GPU 회귀 테스트 8개 통과.
- Swift frontend 문법 검사 및 Xcode 프로젝트/Info.plist/PrivacyInfo plist 검사 통과.
- 편집 기록·실행 취소 영속 저장, 원본 보호, 얼굴 형태 잠금 검증용 XCTest 추가.
- 로컬 iOS SDK 부재로 실제 iOS 컴파일·기기 검증은 GitHub CI 및 Xcode 설치 후 수행 필요.
- App Store 인증서/API 키는 저장소에 포함하지 않음. CI/CD 설정 추가는 실제 서명·심사·출시 완료를 뜻하지 않음.

### 실제 iOS CI 결과

2026-10-13, commit b298b70: GitHub macos-15 / Xcode 26.3 / iPhone 16 Pro iOS 18.5에서 빌드와 XCTest 4개 PASS. 공유 엔진 회귀 8개 PASS. https://github.com/MJ-0701/mellow-photo/actions/runs/38361777195

초기 30ab817 빌드는 Swift package와 앱 아키텍처 불일치로 실패했고 Debug ONLY_ACTIVE_ARCH 설정과 테스트 destination arch 지정으로 해결했습니다. iOS 실기기/서명/스토어 업로드는 미검증입니다.

## 개인 Mac 실행 및 iPhone 출시 준비 보완

2026-10-13, 구현 커밋 `1a14f57`까지의 변경을 기준으로 확인했습니다.

- Xcode 27.0으로 Mac Release 앱 빌드 성공. 실행 파일 arm64·x86_64 포함, 최소 macOS 14 확인. Intel 실기기 실행은 미검증.
- 독립 검수: GPU 엔진 테스트 8개, 앱 엄격한 서명 검사, ZIP CRC·SHA256·압축 해제 후 서명 검사 통과. 임시 서명이며 Apple 공증은 아님.
- 현재 StudioStore로 공개 HEIC 사진 실제 가져오기, 얼굴 1명 감지, 노출·피부 조정 미리보기, 실행 취소·복귀 통과. JPEG·PNG 저장·재해독·동명 파일 보호·원본 바이트 보존 확인. 512×512 시험 이미지이며 고해상도 성능 검증을 대신하지 않음.
- 최신 Mac 앱의 시작 화면은 확인. 사진 선택창에서 열기 버튼 비활성 상태와 화면 자동화 `noWindowsAvailable`/timeout 오류로 파일 선택창·저장창 전체 UI 검증은 완료하지 못함. 처리 경로 검증과 구분함.
- iPhone 손상 기록 보존, 저장 실패 시 사진 제거 중단, 손상 사진 재시도·제거 경로와 회귀 테스트 3개 추가. 독립 정적 검수에서 미해결 P1/P2 없음.
- 로컬 Xcode 27.0 unsigned iPhone Release 빌드와 bundle ID·iPhoneOS·arm64·Assets.car·PrivacyInfo 검사 통과. 앱과 XCTest의 generic simulator build-for-testing 성공.
- 로컬 iOS 27 시뮬레이터 실행은 runtime path not found로 차단됨. 실행 테스트 통과로 기록하지 않음. GitHub CI의 iOS 18.5 실행 결과는 별도 확인.
- GitHub CI `1a14f57` 최종 성공: GPU 엔진 8개, iPhone XCTest 7개와 unsigned Release iPhone 빌드·bundle 검사 통과. https://github.com/MJ-0701/mellow-photo/actions/runs/38364061937
- 앱 소개·심사 안내 초안 준비. 초대코드 제한은 심사 위험을 고려해 제외. 서명·스토어 업로드·실기기·48MP·Apple 심사는 아직 미완료.

## 구조 리팩토링 A (2026-10-14)

2026-10-14, 브랜치 `apple-modulith` 커밋 `13be3db` 기준. Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 0. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음 확인을 포함.
- 패키지 `swift test` 69개 통과: MellowShared 8, MellowRendering 22, MellowLibrary 25, MellowExport 4, MellowEditing 10.
- 앱 XCTest: iPhone 18 Pro 시뮬레이터 23개, iPad Pro 13-inch (M5) 시뮬레이터 23개, macOS 24개 모두 통과.
- `./scripts/build-apple.sh ios-device`: 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo plist 검사, 번들 ID·iPhoneOS·Assets.car 검사 통과.
- `./scripts/build-apple.sh mac`: Release 빌드 arm64·x86_64 포함, `codesign --verify --deep --strict` 통과. 경고는 기존 `WarpKernel.swift:15` `init(source:)` 지원 중단 경고뿐.
- 전체 리뷰 후속 수정(커밋 `da3348f` 기준)에서 자동 검증을 다시 실행: `./scripts/test-apple.sh` 종료 코드 0, 패키지 `swift test` 71개 통과(MellowShared 8, MellowRendering 22, MellowLibrary 26, MellowExport 4, MellowEditing 11), 앱 XCTest iPhone 18 Pro 시뮬레이터 26개·iPad Pro 13-inch (M5) 시뮬레이터 26개·macOS 27개 통과, `./scripts/build-apple.sh ios-device`·`mac` 통과. 후속 수정의 화면 동작(핀치 줌, Finder 열기, 입력 중 ⌘Z)은 실기동으로 확인하지 않음.

### 출시본 v1 세션 복원 (iPhone 18 Pro 시뮬레이터)

- 앱 컨테이너 `Library/Application Support/MellowPhoto/` 바로 아래에 `shared/fixtures/session-v1.json`과 데모 사진 사본 2장(`.heic`, `.jpg` 확장자의 PNG)을 출시본 레이아웃 그대로 두고 실행.
- 화면 캡처로 확인: 사진 2장 복원, 첫 사진 선택, 노출 0.40 표시와 밝아진 미리보기, 두 썸네일 모두 편집 표시, 실행 취소·다시 실행 버튼 활성 모양, 프리셋 목록에 저장된 "포근한" 노출(기본 프리셋 "포근한"과 같은 이름으로 두 번 보임), 상태줄 "2장".
- 종료 후 파일로 확인: `session.json`이 `"schemaVersion":2`로 다시 쓰임. 첫 사진 노출 0.4·피부 정돈 0.3·얼굴 형태 0.2·대상 얼굴 1, spot·warp 작업 2개, 실행 취소 2단계·다시 실행 1단계 보존. 두 번째 사진 따뜻함 -0.1. 프리셋 "포근한"(노출 0.15·채도 0.92·따뜻함 0.25·피부 0.3) 보존. 사진 사본은 옛 위치에서 그대로 읽힘.
- 재실행 후에도 같은 화면으로 복원됨(화면 캡처).
- 얼굴 1명 감지와 실행 취소 2단계 실제 동작은 시뮬레이터를 조작할 수 없어 iOS에서 확인하지 못함.

### 플랫폼별 실기동

- iPhone 시뮬레이터: 세로 compact 편집 화면(사진 줄·캔버스·동작 바·도구 탭·슬라이더 세로 배치)을 화면 캡처로 확인. 실행과 화면 캡처만 했고 탭 조작은 하지 않음.
- iPad Pro 11-inch (M5) 시뮬레이터: v2 세션과 작업 사본을 컨테이너에 넣고 실행. 세로 방향에서 3단 레이아웃(사이드바 "내 사진 2", 캔버스, 오른쪽 조정 패널)을 화면 캡처로 확인. 탭 조작은 하지 않음.
- Mac: 샌드박스·임시 서명된 Release 앱으로 확인. 방법을 항목마다 적음.
  - 화면 캡처: 실행 시 컨테이너의 기존 세션(사진 1장) 복원.
  - 접근성 조작(메뉴) + 화면 캡처 + session.json 파일 확인: 실행 취소·다시 실행. 미리보기, 버튼 상태, 파일의 작업·실행 취소·다시 실행 개수가 함께 바뀜.
  - 접근성 조작 + 화면 캡처: 인물 탭 "얼굴 1명".
  - 접근성 속성 확인 + 화면 캡처: 얼굴 미세 조정 슬라이더와 얼굴 선택 비활성, 피부 정돈 활성, 잠금 안내 문구. 잡티 보정 기록은 이번 실행의 탭이 아니라 컨테이너에 이미 있던 세션의 것임.
  - 접근성 조작 + 화면 캡처: 노출 슬라이더 0.90과 밝아진 미리보기, 원본 비교 전환.
  - 접근성 조작 + 저장된 파일 확인: 폴더 저장. 1254×1254 JPEG, 상태 "1장 저장 완료".
  - 앱 메뉴로 종료, 재실행 후 화면 캡처 + session.json 파일 확인: 노출 0.90 복원.
- Mac 조작 방식: 첫 가져오기 시도에서 전역 키 입력(⇧⌘G·경로 입력·Return)을 썼으나 가져오기는 되지 않았고, 앱 창이 사라져 앱을 다시 실행해야 했음. 그 뒤로는 Mellow Photo를 대상으로 한 접근성 액션만 사용했으나, 예외로 내보내기 메뉴를 닫으려고 전역 Escape를 1회 보냄.
- Mac 검증 뒤 컨테이너의 세션과 사본은 검증 전 백업으로 되돌림.
- 참고: 같은 날 적응형 화면 구현 단계(커밋 `6cb21d9`)에서 Debug 빌드로 Mac 파일 가져오기, 잡티 샘플·대상 탭, ⇧⌘S 저장을 해 본 기록이 그 단계의 구현 보고서에 있음(저장소 문서 아님). 이 절의 검증이 아니라 배경 정보이며, 이번에는 다시 하지 않음.

### Mac 샌드박스

- Release 앱 권한: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`. 데이터는 `~/Library/Containers/com.mj.mellowphoto/`에 저장됨을 확인.
- `container-migration.plist`가 번들에 포함됨을 확인. 구 Mac 앱 폴더를 컨테이너로 옮기는 실제 이전은 미검증(이 Mac에는 이미 컨테이너가 있음).
- `CODE_SIGNING_ALLOWED=NO`로 만든 Debug 앱은 권한이 없어 샌드박스 밖에서 실행되고 컨테이너 세션을 읽지 않음. 테스트용 빌드의 특성이며 배포본과 다름.

### 미검증

- 실기기(iPhone·iPad·Intel Mac), 48MP 원본, HDR 사진, 서명·공증·스토어 업로드.
- iOS에서 PhotosPicker·파일 가져오기, 사진 앱 저장과 권한 요청, 잡티·변형 탭, 슬라이더 조작, 원본 비교, 얼굴 감지 표시.
- iPad 가로 방향(시뮬레이터 회전 불가), 드래그 앤 드롭, Option+클릭 샘플 재지정, ⌘O.
- 이번 Mac 실행에서 파일 가져오기와 잡티 탭: 전역 키 입력으로 한 첫 가져오기 시도가 실패했고, 사용자가 같은 Mac을 쓰는 중이라 이후 전역 키 입력·클릭을 다시 쓰지 않음.
- 실제 Mac의 구 앱 폴더 → 샌드박스 컨테이너 이전.
- iOS 대화형 실기동(가져오기→편집→실행 취소→사진 앱 저장)은 셸에서 시뮬레이터 탭이 불가하고 네이티브 시뮬레이터 도구는 `sudo xcode-select` 전환이 필요해 미실시. 첫 `apple-v*` 태그 전 사용자가 수행해야 함.

## B0 기본 편집 세트 (2026-10-15)

2026-10-15, 브랜치 `b0-basic-editing` 커밋 `032399a` 기준(이 절을 쓴 문서 커밋 직전). Apple Silicon / macOS 26.6.2 / Xcode 27.0. 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 0. 모듈 의존성·import 검사 통과, `swift format lint --strict` 통과, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음.
- 패키지 `swift test` 136개 통과: MellowShared 29, MellowRendering 56, MellowLibrary 29, MellowExport 4, MellowEditing 18.
- 앱 XCTest: iPhone 18 Pro 시뮬레이터 46개, iPad Pro 13-inch (M5) 시뮬레이터 46개, macOS 47개 모두 통과. Mac이 하나 많은 것은 Mac 전용 폴더 저장 테스트 때문입니다.
- `./scripts/build-apple.sh ios-device`: 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·iPhoneOS·Assets.car 검사 통과.
- `./scripts/build-apple.sh mac`: Release 빌드 arm64·x86_64 포함, 엄격한 서명 검사 통과.
- 두 빌드의 경고는 기존 `WarpKernel.swift`의 Core Image 커널 API 지원 중단 경고 하나뿐입니다.

### 화면 실기동 대신 한 검증

계획은 Mac 앱을 접근성 조작으로 실행해 보는 것이었지만, 사용자가 같은 Mac을 쓰는 중이라 앱 데이터 폴더를 바꾸거나 전역 입력을 보내지 않는다는 규칙과 맞지 않아 하지 않았습니다. 대신 앱 모델을 화면 없이 끝까지 돌리는 시나리오 테스트 3개를 추가했고, 위 세 대상(iPhone·iPad 시뮬레이터, Mac)에서 모두 통과했습니다.

- 정사각형 데모 사진: 가져오기 → 필터 "필름" 강도 0.5 → 자동 보정(레시피가 바뀌고 안내 문구가 뜨는지) → 하이라이트 −0.5 → 자르기 1:1 → 수평 5° → 90° 회전 → 내보내기 → 저장 파일이 정사각형인지.
- 가로 3:2 사진: 1:1로 자른 뒤 90° 회전해도 저장 파일이 정사각형인지. 고치기 전에는 4:9 비율로 저장되는 것을 테스트로 먼저 확인했습니다.
- 가로 3:2 사진: 1:1 자르기를 왼쪽 끝으로 옮긴 뒤 좌우 반전하면 자르기 영역도 오른쪽 끝으로 옮겨 같은 부분이 보이는지.

이 테스트는 화면 배치, 터치·드래그, 썸네일 표시, 실제 사진에서의 색감을 확인하지 않습니다.

### 룩 10종

룩 10종을 실제 사진이나 데모 사진으로 눈으로 본 확인은 하지 않았습니다. 자동 테스트는 10종이 모두 렌더되고, 강도 0이 원본과 같고, 강도 1·0.5가 원본과 다른 것까지만 봅니다. 수치는 세피아 하나만 바꿨습니다(따뜻함 0.6 → 0.7, 비네팅 0.15 → 0.1). 작은 회색 시험 이미지의 모서리에서 따뜻함과 비네팅이 서로 상쇄돼 강도 0.5 결과가 원본과 같게 나왔기 때문이며, 보기 좋고 나쁨을 판단해 바꾼 것은 아닙니다.

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 도구 줄: iPhone 세로 화면에서 가로 스크롤과 캔버스를 가리는 정도, iPad·Mac 인스펙터에서 잘리지 않고 스크롤되는지, Mac에서 마우스로 스크롤 막대를 끌어 잡티·변형까지 갈 수 있는지(트랙패드만 쓰는 오버레이 스크롤 막대 설정에서는 막대가 숨을 수 있음), '자동'이 선택 상태 없이 버튼으로만 동작하는지.
- 필터 칩: 썸네일이 채워지기 전 스피너, 썸네일 표시, 강도 슬라이더가 필터를 고를 때만 나오는지.
- 룩 10종을 실제 인물·풍경·실내 사진에서 보고 좋은지 판단하는 것. 좋지 않은 룩은 수치 조정이 필요합니다.
- 자르기 화면: 바깥 어둡게, 손잡이 8개, 모서리·변 드래그와 안쪽 이동, 비율 고정 드래그, 확대한 상태에서의 드래그, 회전·반전 뒤 화면 모습.
- 자른 사진에서 잡티 도구의 샘플 고리 크기가 실제 보정 범위와 맞아 보이는지.
- 선명도가 미리보기와 저장 결과에서 비슷하게 보이는지.

이전 절에서 넘어온 항목:

- 실기기(iPhone·iPad·Intel Mac), 48MP 원본(하이라이트·그림자 조정이 큰 사진에서 얼마나 느린지 포함), HDR 사진, 서명·공증·스토어 업로드.
- iOS 대화형 실기동(가져오기 → 편집 → 실행 취소 → 사진 앱 저장), 사진 앱 저장 권한 요청.
- iPad 가로 방향, 드래그 앤 드롭, Mac Option+클릭 샘플 재지정, ⌘O.
- 실제 Mac의 구 앱 폴더 → 샌드박스 컨테이너 이전.

### 나중에 정할 동작

- 잡티 브러시 반경은 원본 사진 기준입니다. 자른 사진에서는 화면 고리만 자른 비율만큼 크게 그립니다. 반경 자체를 화면 기준으로 바꿀지는 정하지 않았습니다.
- 오류가 여러 개 겹치면 화면에는 하나만 보입니다.
- 렌더 엔진은 필터 칩을 만들 작은 썸네일(사진당 약 190KB)을 사진을 편집에서 뺄 때까지 메모리에 남깁니다. 미리보기 캐시와 달리 개수 상한이 없어, 편집 목록의 사진 수(최대 40장)만큼 쌓입니다. 앱이 만든 필터 칩 이미지(사진당 10장)도 같은 시점까지 남습니다.

## 인물 보정 B 피부 (2026-10-15)

2026-10-15, 브랜치 `beauty-b-to-f` 커밋 `42a1cd9` 기준(자동 잡티 복구 원본 수정 직후). Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터. 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 **0**. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트까지 한 번에 통과했습니다.
- 이력: 커밋 `70be778`에서의 실행은 Mac 단계 직전에 `line 19: parallel[@]: unbound variable`로 멈춰 종료 코드 1이었습니다. macOS bash 3.2가 `set -u`에서 빈 배열 확장을 오류로 본 탓이며 커밋 `b06c7da`에서 고쳤습니다.
- 패키지 `swift test` 175개 통과: MellowShared 37, MellowRendering 84, MellowLibrary 30, MellowExport 4, MellowEditing 20.
- 앱 XCTest(모두 `test-apple.sh` 안에서): iPhone 18 Pro 시뮬레이터 50개, iPad Pro 13-inch (M5) 시뮬레이터 50개, macOS 51개 모두 통과. Mac이 하나 많은 것은 Mac 전용 폴더 저장 테스트 때문입니다.
- `./scripts/build-apple.sh ios-device`(커밋 `42a1cd9`): 종료 코드 0. 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·iPhoneOS·Assets.car 검사 통과.
- `./scripts/build-apple.sh mac`(커밋 `42a1cd9`): 종료 코드 0. Release 빌드 arm64·x86_64 포함, 서명 검사 통과.
- 두 빌드의 경고는 Core Image 커널 언어 API 지원 중단 경고뿐입니다. 기존 `WarpKernel.swift`(`CIWarpKernel`)와 이번에 더한 `SkinKernels.swift`(`CIColorKernel`, 커널 두 개)입니다. iPhone 빌드 로그에는 이 경고만 낸 컴파일 단계에 xcodebuild가 붙인 "failed with exit code 0" 머리줄이 하나 있지만 빌드와 스크립트는 종료 코드 0입니다.

### 자동 테스트가 확인하는 것

- 합성 얼굴에서 피부 보정을 켜도 눈·입 픽셀과 얼굴 윤곽 안 배경 픽셀은 바뀌지 않고, 볼은 바뀝니다.
- 세 대역 주파수 분리: 모공 대역 분산은 ±10% 안에 남고(구현 때 측정 −5.4%), 중간(얼룩) 대역 분산은 줄어듭니다. 분리 단독은 절반 아래(구현 때 측정 0.19배), 피부 단계 전체는 0.6배 아래가 기준입니다.
- 잡티 검출: 합성 얼굴에 심은 잡티 5개를 모두 찾고 눈 바로 옆 점은 무시합니다. 깨끗한 피부와 얼굴 없는 사진은 아무것도 찾지 않습니다. 얼굴당 상한을 지킵니다. 분석을 절반으로 축소해도 찾은 위치가 원래 자리로 돌아옵니다.
- 자동 잡티 복구: 심은 잡티가 지워지고, 고른 얼굴의 잡티만 지워집니다. 복구 원본이 코·입술에 걸리면 반대쪽을 쓰고 입술 픽셀은 그대로입니다.
- 자동 잡티 복구 원본은 얼굴 피부 다각형 안이어야 합니다. 가운데 쪽은 눈이고 바깥쪽은 피부 다각형 밖인 관자놀이 잡티는 건너뛰어 픽셀이 그대로입니다. 가운데 쪽 원본이 이웃 잡티 위면 반대쪽 피부를 쓰고 두 잡티 모두 지워집니다.
- 데모 인물 사진의 실제 Vision 특징점으로 볼은 피부 마스크 안, 눈동자는 밖입니다. 데모 사진에서 찾은 잡티는 상한 안이고 눈·입술 밖입니다.
- 얼굴 폭은 좁게·넓게 두 방향 모두 렌더됩니다.
- 옛 키 이행: `portrait.skinSmoothing`·`faceSlim`이 새 키로 읽히고 다시 쓰이지 않습니다. 새 키가 있으면 새 키가 이깁니다. B0 세션 파일의 실행 취소 기록 안 레시피도 이행됩니다. 스키마에는 옛 키가 지원 중단 표시로 남아 있습니다.
- 편집 규칙: 수동 편집 뒤 얼굴형·대상 얼굴 잠금, 자동 잡티는 잠기지 않고 실행 취소 한 번에 되돌아감, 잠긴 사진에 프리셋을 적용해도 얼굴형 유지, 얼굴이 있을 때 자동 보정은 자동 잡티를 켜고 얼굴 폭은 그대로 둠.
- 크기가 다른 타원 마스크를 한 렌더에 섞어도 큰 타원의 윤곽이 무너지지 않습니다(아래 수정의 회귀 테스트).
- 시나리오(화면 없이 앱 모델로): 데모 인물 사진 가져오기 → 뷰티에서 피부 보정 0.5 + 자동 잡티 → 얼굴 탭에서 얼굴 폭 −0.5 → 미리보기가 바뀜 → 내보내기 파일이 정사각형.

이 테스트는 합성 얼굴과 데모 사진 한 장으로 돌며, 실제 인물 사진에서 보기 좋은지는 판단하지 않습니다.

### 구현 중 고친 기존 결함

- 타원 마스크(`MaskBuilder.ellipse`): 크기가 다른 타원이 한 렌더 안에 있으면 Core Image가 같은 그라데이션을 재사용해 큰 타원의 단단한 중심과 경계가 뭉개졌습니다(커밋 `6ceed7b`에서 수정). 이 때문에 B0까지의 수동 잡티 브러시에서 크기가 다른 잡티를 여러 개 찍으면 중심이 흐려졌고, 옛 피부 정돈의 눈·입 보호도 새고 있었습니다(코드 리뷰 측정 기준 약 40%). 수동 잡티와 자동 잡티 모두 이제 설계한 윤곽대로 지웁니다. 실제 사진에서 수동 잡티 결과가 B0 때와 조금 달라 보일 수 있습니다.

### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)

- 자동 잡티 복구 비용: 4032×3024 합성 이미지, 얼굴 하나, 잡티 40개를 이 Mac 디버그 빌드에서 렌더하면 7회 중앙값 23~25 ms였습니다. 노출 필터 하나(26 ms)와 같은 수준입니다. 커밋하지 않은 임시 측정이며 시뮬레이터·실기기·48MP 원본은 재지 않았습니다.
- 복구 원본이 코·입술·눈 제외 영역에 걸리거나, 얼굴 피부 다각형 밖이거나, 그 얼굴의 다른 잡티와 겹치면 반대쪽을 쓰고, 양쪽 다 안 되면 그 잡티는 건너뜁니다(커밋 `42a1cd9`에서 피부 다각형·이웃 잡티 조건 추가). 위 비용 측정은 이 조건을 넣기 전 값입니다.

### 스펙과 다르게 한 것

- 피부색 가중치의 볼 색 기준은 볼 평균만 씁니다(분산은 쓰지 않음).
- 잡티 검출 범위는 얼굴 상자가 아니라 피부 마스크 범위입니다. 이마가 얼굴 상자 위로 나가서, 상자만 보면 이마 잡티를 놓쳤습니다.
- 잡티(`BlemishSpot`)에 얼굴 번호를 담습니다. 얼굴 하나만 고른 경우 그 얼굴 잡티만 지우기 위해서입니다.
- 옛 키 `portrait.skinSmoothing`·`faceSlim`은 레시피 스키마에 읽기 전용(지원 중단 표시)으로 남겼습니다. B0에서 저장한 파일이 스키마 검증을 통과해야 해서입니다.
- `scripts/test-apple.sh`의 iPhone·iPad 시뮬레이터 앱 테스트는 병렬 테스트를 끄고 돕니다(커밋 `a167917`). 복제 시뮬레이터를 켰다 지우는 과정이 시뮬레이터 SpringBoard를 반복해서 죽였기 때문입니다. 이 수정이 커밋 `70be778` 실행의 Mac 단계 실패를 만들었고, 커밋 `b06c7da`에서 고쳤습니다.

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 인물 사진에서의 피부 보정 느낌: 플라스틱처럼 보이지 않는지, 강도 1에서도 자연스러운지.
- 자동 잡티가 주근깨나 점을 잡티로 지우는지.
- 머리카락이 이마·볼을 덮은 사진에서 피부 영역 경계가 티 나지 않는지.
- 강한 조명·역광 사진에서 피부 영역이 흔들리지 않는지.
- 여러 얼굴 사진: 얼굴 번호(왼쪽부터), 한 얼굴만 고를 때 다른 얼굴이 그대로인지.
- 48MP 원본 저장 속도와 메모리(얼굴마다 큰 흐림을 두 번 계산함).
- 뷰티 패널 화면: 피부·얼굴 탭 전환, 자동 잡티 스위치, 얼굴 폭 슬라이더가 0 근처에서 0에 붙는지, 잠금 안내, 좁은 화면 배치.
- 실기기(iPhone·iPad)에서 위 항목 전부.

이전 절(B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

## 인물 보정 C 얼굴 리셰이프 (2026-10-15)

2026-10-15, 브랜치 `beauty-b-to-f` 커밋 `7841fb2` 기준(얼굴 탭 안내 문구 수정 직후). Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5)). 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트까지 한 번에 통과했습니다.
- 로컬 `./scripts/test-apple.sh`는 이제 `MELLOW_IOS_TESTS=1`이 없으면 iPhone·iPad 시뮬레이터 앱 테스트를 건너뜁니다(CI는 항상 실행). 시뮬레이터가 부팅 직후 SpringBoard 오류로 Mac에 오류 창을 띄우기 때문입니다. 이번 실행에서도 iPad 시뮬레이터의 SpringBoard 오류 보고서가 하나 생겼지만 그 시뮬레이터의 테스트 52개는 모두 통과했습니다. 실행 뒤 두 시뮬레이터는 꺼진 상태였습니다.
- 패키지 `swift test` 220개 통과: MellowShared 37, MellowRendering 128, MellowLibrary 30, MellowExport 4, MellowEditing 21. 계획의 예상(212개, Rendering 120)보다 8개 많은 것은 구현 중 더한 테스트(클램프·동공 겹침·손 계산 기대값, 원소 경계 지도, 돌린 얼굴 좌우 판정, NaN) 때문입니다.
- 앱 XCTest(모두 위 실행 안에서): iPhone 18 Pro 시뮬레이터 52개, iPad Pro 13-inch (M5) 시뮬레이터 52개, macOS 53개 모두 통과.
- `./scripts/build-apple.sh ios-device`(커밋 `7841fb2`): 종료 코드 0. 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·에셋 검사 통과.
- `./scripts/build-apple.sh mac`(커밋 `7841fb2`): 종료 코드 0. Release 빌드 arm64·x86_64.
- 두 빌드의 경고는 Core Image 커널 언어 API 지원 중단 경고뿐입니다. 기존 `WarpKernel.swift`(1곳)와 `SkinKernels.swift`(2곳)에 이번 `DisplacementWarp.swift`(4곳: 이동량 지도 색 커널 3개와 샘플링 커널 1개)가 더해졌습니다. 두 빌드 로그 모두 이 경고만 낸 컴파일 단계에 xcodebuild가 붙인 "failed with exit code 0" 머리줄이 하나 있지만 빌드와 스크립트는 종료 코드 0입니다.

### 자동 테스트가 확인하는 것

- 이동량 지도: 원소가 없으면 입력과 같은 바이트, push가 점 표식을 정확한 위치로 옮김(구현 때 측정 오차 0.11px 이하), 음수 방향, 두 원소의 이동이 각 이동의 합과 같음, scale 확대, 원소별 상한, 띠의 단조·연속과 띠 아래 이동, 가장자리 불투명. 원소 영향 경계 안에서만 그린 결과가 전체 크기로 그린 결과와 같고 경계 밖은 입력 바이트 그대로입니다.
- 얼굴 좌표계: 30° 기울인 얼굴에서 축이 같이 돌고 높이는 유지, 뒤집힌 얼굴에서 위쪽이 눈을 향함, 눈동자가 없거나 겹치면 눈 영역 중심 → roll 순으로 대체.
- 얼굴형 원소: 얼굴 폭 −1은 왼쪽 윤곽을 +x·오른쪽 윤곽을 −x로 밂, 턱선·광대·이마·턱 길이·눈·코·입 방향, 열 항목 좌우 대칭, 30° 기울면 원소도 30° 회전, 범위 밖 값은 잘린 값과 같은 원소, 유한하지 않은 값은 0, yaw 약화와 옆얼굴에서 원소 없음, 특징점이 빠진 항목만 건너뜀, 두 눈동자가 겹치면 눈 원소를 만들지 않음, 돌린 얼굴에서 눈 간격·턱선이 두 눈 중점 기준으로 대칭, ±1 조합 세 가지에서 접힘 없음(야코비안 최솟값 > 0.2), 데모 사진의 실제 특징점으로 열 항목 모두 원소 생성.
- 얼굴 단계 렌더: 얼굴 폭을 줄이면 윤곽 표식이 중심 쪽으로 이동, 범위 밖 값이 잘린 값과 같은 결과, 고른 얼굴만 변형, 특징점 없이 상자만 있는 얼굴은 그대로, B0 `faceSlim` 0.3 레시피가 계속 좁힘, 체형 원소는 아직 빈 배열.
- 앱: 얼굴 탭 슬라이더 10개가 드래그마다 실행 취소 한 단계, 잠금 시 10개 모두 거부.
- 시나리오(화면 없이 앱 모델로): 데모 사진 가져오기 → 피부 보정 0.5 + 자동 잡티 → 얼굴 폭 −0.5·눈 크기 0.3·미소 0.4로 미리보기가 다시 바뀜 → 내보내기 파일이 정사각형. iPhone·iPad 시뮬레이터에서도 통과했으므로 이동량 지도 커널(`destCoord()`를 쓰는 색 커널 포함)이 iOS 시뮬레이터에서 컴파일·실행됩니다. 시뮬레이터 결과이므로 실기기 GPU에서의 동작은 이것으로 확인되지 않습니다.

이 테스트는 합성 얼굴과 데모 사진 한 장으로 돌며, 실제 인물 사진에서 보기 좋은지는 판단하지 않습니다.

### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)

- 접힘: 합성 얼굴에서 아홉 항목 ±1 × 미소 0·1의 1024조합 중 야코비안 최솟값 0.496(테스트 기준 0.2). 똑바른 합성 얼굴 기준이며 실제 사진은 재지 않았습니다.
- 메모리: Mac, 8000×6000 비트맵 입력, 얼굴 1개에서 최대 메모리가 전체 크기 지도 875 MB → 원소 경계 안 지도 832 MB. 같은 사진에 색 필터 하나만 걸어도 809 MB라 대부분은 전체 크기 렌더 자체의 비용입니다. 커밋하지 않은 임시 측정이며 시뮬레이터·실기기·48MP는 재지 않았습니다.

### 스펙과 다르게 한 것

- 이동량 지도를 그라데이션 덧셈 대신 Core Image 커널 언어 색 커널로 만듭니다. 그라데이션 덧셈은 음수 이동량을 보존하지 못합니다. 색 커널 예외 경로(일반 커널로 바꾸기)는 쓰지 않았습니다.
- 지도와 샘플링을 원소 영향 경계의 합집합 안에서만 하고 원본 위에 합성합니다. 큰 사진의 중간 버퍼를 줄이기 위해서입니다. 스펙 결정 표와 1.5절을 고쳤습니다.
- 값 범위 정의를 MellowShared `AdjustmentRange`로 옮겼습니다. 렌더 모듈이 편집 모듈을 쓸 수 없기 때문입니다. `EditingPolicy`는 같은 이름으로 그대로 내보냅니다.
- 광대는 "눈 높이 윤곽점" 대신 각 쪽 맨 위 윤곽점을 씁니다. 같은 쪽 윤곽점 여러 개는 이동을 나눠 가집니다.
- `FaceShapeRig.primitives`에 `tuning` 인자를 더했습니다.
- scale·band의 원소별 상한은 이동 길이 대신 배율·늘림 비율(±`shapeDisplacementLimit`)로 정의했습니다.
- yaw 약화는 cos(|yaw|) / cos(0.35)라 0.35에서 끊기지 않습니다.
- 계획에 없던 방어: 두 눈 중심이 얼굴 폭의 5% 이하로 가까우면 눈 원소를 만들지 않음, 유한하지 않은 값은 0, 눈 간격·턱선의 좌우 판정은 얼굴 상자 중심 대신 두 눈 중점(얼굴 폭·광대는 상자 중심 그대로).

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 인물 사진에서 얼굴형 10종의 느낌, 최대값이 과하거나 약한지.
- 여러 슬라이더를 함께 끝까지 올린 실제 사진(접힘·뭉개짐).
- 기울어진 얼굴, 고개를 돌린 얼굴(약화가 자연스러운지).
- 눈 특징점이 없는 얼굴에서 쓰는 Vision roll 부호.
- 특징점 없이 상자만 있는 얼굴에서 B0 세션의 얼굴 미세 조정(옛 `faceSlim`)이 더는 적용되지 않는 점.
- 얼굴 가까운 문틀·벽 같은 직선 배경 휨.
- 여러 얼굴 사진: 고른 얼굴만 바뀌는지, 얼굴끼리 가까울 때.
- 48MP 원본 저장 속도와 메모리.
- 얼굴 탭 화면: 슬라이더 10개 배치, 0 근처에서 0에 붙는지(미소 제외), 잠금 안내, 안내 문구, iPhone 좁은 화면의 긴 스크롤.
- 실기기(iPhone·iPad)에서 이동량 지도 커널과 마스크 합성, 그리고 위 항목 전부.

이전 절(B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

## 인물 보정 D 눈·치아·입술·배경 (2026-10-15)

2026-10-15, 브랜치 `beauty-b-to-f` 커밋 `3f6c8b7` 기준(배경 도구·Vision 인물 분석 연결 직후, 이 절을 쓰는 문서 커밋 바로 앞). Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5)). 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트까지 한 번에 통과했습니다.
- 패키지 `swift test` 257개 통과: MellowShared 37, MellowRendering 163, MellowLibrary 30, MellowExport 4, MellowEditing 23. 계획의 예상(253개, Rendering 159)보다 4개 많은 것은 구현 중 더한 테스트(눈동자 마스크 픽셀, 흰자 판별 규칙, 고른 얼굴만 바뀌는 눈·입 보정, 세로 사진에서 가로 마스크를 축별로 키우기) 때문입니다.
- 앱 XCTest(모두 위 실행 안에서): iPhone 18 Pro 시뮬레이터 55개, iPad Pro 13-inch (M5) 시뮬레이터 55개, macOS 56개 모두 통과.
- `./scripts/build-apple.sh ios-device`(커밋 `3f6c8b7`): 종료 코드 0. 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·에셋 검사 통과.
- `./scripts/build-apple.sh mac`(커밋 `3f6c8b7`): 종료 코드 0. Release 빌드 arm64·x86_64, 서명 검사 통과.
- 두 빌드의 경고는 Core Image 커널 언어 API 지원 중단 경고뿐입니다. 기존 `WarpKernel.swift`·`SkinKernels.swift`·`DisplacementWarp.swift`에 이번 `FeatureKernels.swift`(색 커널 2개: 흰자·치아 가중치, 색 이동)가 더해졌습니다. C 절과 같이 두 빌드 로그에 "failed with exit code 0" 머리줄이 하나씩 있지만 빌드와 스크립트는 종료 코드 0입니다.
- 실행 전후 새 SpringBoard 오류 보고서는 생기지 않았습니다(가장 최근 보고서가 실행 전과 같은 `SpringBoard-2026-10-15-180724.ips`). 테스트에 쓴 두 시뮬레이터는 실행 뒤 꺼진 상태였고, 실행 전부터 켜져 있던 다른 시뮬레이터(iPhone 17e)는 건드리지 않았습니다.

### 자동 테스트가 확인하는 것

- 분석 묶음: 얼굴·잡티만 넘기는 옛 생성자와 묶음 생성자가 같은 대상 얼굴·잡티를 줌, 다각형 마스크 비트맵을 렌더 사이에 다시 쓰고 캐시 유무 결과가 같은 바이트, 상한(32개)에 차면 비움, 미리보기 캐시에서 밀려난 사진은 마스크를 놓음.
- 인물 분석: 데모 사진에서 얼굴 가운데는 사람·왼쪽 위 구석은 배경, 단색 빈 사진은 사람 없음, 스텁 분석기 실패가 사진 준비를 막지 않고 실패 사유로 남음, 분석기를 주지 않으면 사람 없음.
- 영역 마스크: 눈 마스크 밖(눈썹·눈꺼풀)은 0, 동공 중심·대체 중심과 반지름, 안쪽 입술 다각형을 넓혀도 붉은 입술은 치아에서 빠짐, 다문 입은 치아 마스크 없음, 입술 고리, 특징점 없는 얼굴, 데모 사진의 실제 특징점으로 네 마스크 생성.
- 눈·입 렌더: 흰자가 밝아지고 홍채 휘도 분산이 늘며 눈 밖은 같은 바이트, 치아는 파랑이 늘고 치아 밖은 같은 바이트, 다문 입은 치아 미백 1에서도 변화 없음, 입술은 채도가 늘고 입술 밖은 같은 바이트, 범위 밖 값은 자른 값과 같음, 특징점이 빠진 항목만 건너뜀, 고른 얼굴만 바뀜.
- 배경 흐림: 마스크가 없거나 값이 0이면 같은 바이트, 사람 안쪽은 같은 바이트, 가로·세로 배율을 따로 적용(세로 사진에 가로 마스크 포함), 가장자리 불투명, 범위 밖 값, 인물 분석이 실패하면 미리보기·저장 모두 흐림만 빠짐, 원본 해상도 렌더에서 마스크 위치.
- 편집: 눈·입·흐림 값은 0…1로 자르고 수동 편집이 있어도 잠기지 않음, 프리셋·일괄 적용이 두 값을 복사, 얼굴이 있으면 자동 보정에 눈 또렷하게 0.2.
- 앱: 눈·입 탭 슬라이더 세 개가 드래그마다 실행 취소 한 단계, 배경 도구 상태 세 가지(사용 가능·사람 없음·분석 실패), 인물 분석 실패 시 가져오기 오류 창 없음.
- 시나리오(화면 없이 앱 모델로): 데모 사진 가져오기 → 피부 보정 0.5 + 자동 잡티 → 얼굴형 3개 → 눈 또렷하게 0.5 → 배경 흐림 0.5로 미리보기가 다시 바뀜 → 내보내기 파일이 정사각형. 얼굴과 인물 마스크는 스텁입니다. iPhone·iPad 시뮬레이터에서도 통과했으므로 `FeatureKernels` 색 커널과 배경 흐림 필터가 iOS 시뮬레이터에서 컴파일·실행됩니다. 실제 `VisionPersonAnalyzer`는 macOS 패키지 테스트에서만 돌았고, 시뮬레이터·실기기에서는 돌지 않았습니다.

이 테스트는 합성 얼굴과 데모 사진 한 장으로 돌며, 실제 인물 사진에서 보기 좋은지는 판단하지 않습니다.

### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)

- 계획 작성 때(Mac, 데모 사진 1254²): Vision 인물 분석 첫 호출 0.08초(모델 적재), 이후 약 0.01초, 결과는 입력 비율과 무관하게 512×384 고정. 사람 픽셀 비율은 데모 사진 57.6%, 빈 사진 0%.
- 입 열림 비율(안쪽 입술 넓이 / 얼굴 상자 넓이, 합성 얼굴): 벌린 입 0.0114, 다문 입 0.0014(문턱 0.004).
- 합성 얼굴에서 값 1 렌더: 흰자 (199, 189, 184) → (210, 202, 198), 치아 (219, 204, 168) → (223, 206, 200), 입술 (184, 71, 82) → (214, 57, 74), 홍채 영역 휘도 분산 2.16배. 마스크 밖 변화 픽셀 0개(비트맵 입력 기준).
- 배경 흐림(256×192 합성 입력): 사람 안쪽(가장자리 3px 제외) 5220픽셀 중 바뀐 픽셀 0개, 사람 경계의 흐림 경사 약 10px, 단색 입력 테두리의 어두운·투명한 띠 없음.
- 모두 커밋하지 않은 임시 측정이며 실제 인물 사진·시뮬레이터·실기기·48MP는 재지 않았습니다.

### 스펙과 다르게 한 것

- 분석 결과를 `RenderContext` 개별 필드 대신 `PhotoAnalysis` 묶음으로 넘깁니다(B 최종 리뷰 이월). 다각형 마스크 비트맵은 묶음 안 캐시가 사진마다 한 번만 그립니다. 스펙 결정 표와 1.4절을 고쳤습니다.
- 인물 마스크는 "미리보기 크기"가 아니라 Vision 고정 크기(512×384)라 렌더할 때 가로·세로를 따로 키웁니다. 스펙 1.4절을 고쳤습니다.
- "사람 없음" 판정을 마스크 픽셀 중 128/255 이상이 1% 미만인 경우로 정했습니다.
- 입 열림의 "얼굴 면적"은 얼굴 상자 넓이로, 눈 높이는 눈 다각형 경계 상자의 짧은 변으로 계산합니다.
- "노란기(Cb 쪽 이동) 제거"는 감마 BT.601 YCbCr에서 음의 Cb를 0 쪽으로 옮기는 것으로 구현했습니다.
- 준비 전 사진의 배경 흐림도 오류 없이 건너뜁니다.
- 인물 분석 실패는 가져오기 경고에 넣지 않고 배경 도구 안내로만 보입니다.
- 눈·입 보정은 특징점이 없는 얼굴을 건너뜁니다.

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 인물 사진에서 눈·치아·입술 보정의 느낌과 최대값이 과하거나 약한지.
- 노란 조명·진한 그림자에서 흰자·치아 판별.
- 웃는 입·살짝 벌린 입에서 치아 판정 경계.
- 배경 흐림의 머리카락·손가락 경계와 사람 가장자리 색 번짐.
- 여러 사람 사진.
- iPhone·iPad 실기기와 시뮬레이터에서 인물 분석 동작과 시간(앱 테스트는 스텁 마스크만 씀).
- 48MP 원본 저장 속도와 메모리(배경 흐림 반지름 약 120px).
- 눈·입 탭·배경 도구 화면: 슬라이더 배치, 안내 문구, 꺼진 슬라이더.
- 실기기(iPhone·iPad)에서 위 항목 전부.

이전 절(C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

## 인물 보정 E 체형 (2026-10-15)

2026-10-15, 브랜치 `beauty-b-to-f` 커밋 `f3d6f08` 기준(체형 도구·Vision 체형 분석 연결 직후, 이 절을 쓰는 문서 커밋 바로 앞). Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5)). 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트까지 한 번에 통과했습니다.
- 패키지 `swift test` 298개 통과: MellowShared 40, MellowRendering 197, MellowLibrary 30, MellowExport 4, MellowEditing 27. 계획의 예상(293개, Rendering 193 · Editing 26)보다 5개 많은 것은 구현 중 더한 테스트(자동 보정이 체형·배경 흐림을 지키는지, 다시 준비한 사진의 새 분석 2개, 좌우 대칭, 목이 턱을 끌지 않는지) 때문입니다.
- 최종 리뷰 후 수정(목 방향, 빠졌던 체형 렌더 테스트) 뒤 다시 돌린 것: 패키지 `swift test` 301개 통과(MellowShared 40, MellowRendering 200, MellowLibrary 30, MellowExport 4, MellowEditing 27, 렌더 테스트 3개 추가), `swift format lint --strict` 출력 없음, `./scripts/verify-modules.sh` 통과, Mac 앱 테스트 61개 통과. iPhone·iPad 시뮬레이터 앱 테스트, `test-apple.sh` 전체, 두 Release 빌드는 이 수정 뒤 다시 돌리지 않았습니다.
- 앱 XCTest(모두 위 실행 안에서): iPhone 18 Pro 시뮬레이터 60개, iPad Pro 13-inch (M5) 시뮬레이터 60개, macOS 61개 모두 통과. 계획의 예상(58·58·59)보다 2개씩 많은 것은 다시 준비한 사진의 사진 정보 갱신 테스트 2개(인물, 체형) 때문입니다.
- `./scripts/build-apple.sh ios-device`(커밋 `f3d6f08`): 종료 코드 0. 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·에셋 검사 통과.
- `./scripts/build-apple.sh mac`(커밋 `f3d6f08`): 종료 코드 0. Release 빌드 arm64·x86_64, 서명 검사 통과.
- 두 빌드의 경고는 Core Image 커널 언어 API 지원 중단 경고뿐입니다(`WarpKernel.swift` 1곳, `SkinKernels.swift` 2곳, `FeatureKernels.swift` 2곳, `DisplacementWarp.swift` 3곳). `DisplacementWarp.swift`의 다리 띠 색 커널(`bandField`)이 없어져 D보다 한 곳 줄었습니다. 새 경고는 없습니다. 빌드 로그에 "failed with exit code 0" 머리줄이 iPhone 빌드에 하나, Mac 빌드에 둘 있지만 빌드와 스크립트는 종료 코드 0입니다.
- 실행 전후 새 SpringBoard 오류 보고서는 생기지 않았습니다(가장 최근 보고서가 실행 전과 같은 `SpringBoard-2026-10-15-180724.ips`). 테스트에 쓴 두 시뮬레이터는 실행 뒤 꺼진 상태였고, 실행 전부터 켜져 있던 다른 시뮬레이터(iPhone 17e)는 건드리지 않았습니다.

### 자동 테스트가 확인하는 것

- 관절점: 신뢰도 낮은 관절과 없는 관절은 빠짐, 관절 상자와 넓이, Vision 관절 이름 대응과 신뢰도 0 관절 제외, 큰 사람부터 정렬, 실제 `VisionBodyAnalyzer`가 단색 사진에서 0명, 데모 셀카에서 오류 없이 정렬·정규화된 결과를 돌려줌(macOS 패키지 테스트, 데모 셀카의 인원 수는 단정하지 않음).
- 몸통 축: 똑바로 선 사람의 어깨 폭·축, 30° 기운 사람의 축, 엉덩이가 없는 사람, 어깨가 거의 겹치는 옆모습은 축을 정하지 않음, 신뢰도 낮은 어깨가 있으면 체형 없음.
- 체형 분석: 준비 때 관절점을 보관하고 두 어깨가 보일 때만 "체형 있음", 분석 실패가 얼굴·인물 분석을 막지 않고 실패 사유로 남음, 분석기를 주지 않으면 체형 없음, 미리보기 캐시에서 밀려난 사진을 다시 준비하면 새 분석을 돌려주고 캐시에 있으면 다시 분석하지 않음.
- 다리 띠: 매핑이 단조·연속, 양 끝 기울기 0, 이동량 지도에 그리지 않음, 띠 시작 위 행은 같은 바이트, 640.25px 이동이 평행 이동과 0.1px 안, 띠 둘은 거절, push와 한 번에 표식을 옮김.
- 체형 원소: 7항목의 방향과 크기, 관절 누락·낮은 신뢰도는 그 항목만 빠짐, 0·NaN·무한대·범위 밖 값, 이동 상한(`shapeDisplacementLimit`)에 걸려 줄어들지 않음, 기울어진 몸의 축을 따름, 좌우 대칭, 거꾸로·누운 사람은 다리 띠를 건너뜀, 목 +1은 목 아래끝~턱 거리를 늘리고 −1은 줄이며 양쪽 어깨 비탈이 함께 움직이고 턱 이동은 목 최대의 10% 미만, 모든 항목을 겹쳐도 접히지 않음(최소 야코비안 > 0.2, 측정값은 아래).
- 체형 렌더: 다리 길게에서 무릎 표식이 아래로 가고 엉덩이 위는 같은 바이트, 가장 큰 사람만 바뀜, 얼굴형과 체형이 한 번의 샘플링으로 합쳐짐, 범위 밖 값은 자른 값과 같음, 체형 분석이 실패하면 미리보기·저장 모두 체형만 빠짐, 같은 체형 값이 1배·4배 크기에서 4배 이동(미리보기와 저장의 비율 일치), 체형 분석 실패·관절 없음에서도 얼굴형은 바뀌고 체형 값은 픽셀을 하나도 바꾸지 않음, 고른 얼굴이 있어도 체형은 같게 바뀜, 준비 전 사진 저장은 체형을 건너뜀(색만 바꾼 저장과 같은 바이트).
- 편집: 체형 값 클램프, 변경마다 실행 취소 한 단계, 수동 편집이 있으면 체형도 잠김, 자동 보정이 체형·배경 흐림을 바꾸지 않음.
- 앱: 체형 도구 7개 항목이 각각 실행 취소 한 단계, 상태 세 가지(사용 가능·관절 없음·분석 실패), 분석 실패 시 가져오기 오류 창 없음, 수동 편집 잠금이 7개 항목을 모두 거절, 다시 준비한 사진의 체형 정보 갱신.
- 시나리오(화면 없이 앱 모델로): 데모 사진 가져오기 → 피부 → 얼굴형 → 눈 → 배경 → 다리 길게 0.5로 미리보기가 다시 바뀜 → 내보내기 파일이 정사각형. 얼굴·인물 마스크·관절점은 스텁입니다. iPhone·iPad 시뮬레이터에서도 통과했으므로 바뀐 샘플링 커널이 iOS 시뮬레이터에서 컴파일·실행됩니다.

이 테스트는 합성 관절과 스텁으로 돌며, 실제 사람에서 Vision이 관절을 찾는지와 결과가 보기 좋은지는 판단하지 않습니다. 전신 사진 픽스처가 없어 실제 `VisionBodyAnalyzer`가 사람을 찾는 경로는 자동으로 한 번도 돌지 않았습니다.

### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)

- 계획 작성 때(Mac, 1600px 미리보기): Vision 체형 분석 첫 호출 0.08~0.13초(모델 적재), 이후 약 0.005초. 데모 셀카·단색 이미지는 0명이고 `VNDetectHumanRectanglesRequest`도 데모 셀카에서 0명.
- 겹친 체형 원소의 최소 야코비안(문턱 0.2): 똑바로 선 사람 전체 −1 합 0.591·+1 합 0.489, 30° 기운 사람 −1 합 0.562·+1 합 0.459. 단일 항목에서 가장 낮은 것은 허리(약 0.700). 다리 길게 1만은 0.880.
- 목 범위 첫 수정 전후(어깨 폭 204.8px): 턱 끝(목 관절 위 0.28W) 이동 5.07px → 0.00px. 그런데 이 수정 뒤 목 +1은 목 아래끝이 1.59px 올라가 목 아래끝~턱 거리가 1.59px 줄었습니다(방향이 거꾸로, 최종 리뷰 지적).
- 목 최종 수정(어깨선을 내림, 최종 리뷰 후 수정 때 잼): 목 +1에서 목 아래끝~턱 거리 +6.14px(어깨 폭의 3%), −1에서 −6.14px, 턱 끝 이동 0.00px. 목 단일 항목 최소 야코비안 약 0.738, 전체 겹침 최솟값은 그대로 30° 기운 사람 +1 합 0.459.
- 다리 띠 정밀도: 640.25px 이동 표식이 평행 이동과 −0.003px 차이(반정밀도 지도였다면 약 0.28px).
- 얼굴만 편집한 렌더는 다리 띠 변경 전후 SHA-256 30개가 모두 같았습니다.
- 모두 커밋하지 않은 임시 측정이며 실제 전신 사진·시뮬레이터·실기기·48MP는 재지 않았습니다.

### 스펙과 다르게 한 것

- 다리 띠를 이동량 지도에 그리지 않고 샘플링 커널이 smoothstep 식으로 계산하며, 다시 그리는 범위를 골반 행부터 먼 가장자리까지로 줄였습니다. 스펙 결정 표와 1.5절을 고쳤습니다.
- 이동 상한을 하나(0.06)가 아니라 항목마다 따로 두었습니다(허리 0.06·몸 전체 0.035·팔 0.02·허벅지 0.035·어깨 0.04·목 0.03, 모두 0.06 이하). 스펙 결정 표와 5절을 고쳤습니다.
- push 반지름을 이동 / `shapeDisplacementLimit` 이상으로 두어 얼굴과 같은 이동 상한이 체형 이동을 몰래 줄이지 않게 했습니다.
- 목 보정은 목 관절을 위로 미는 대신 어깨선(목 아래끝과 양쪽 승모근 비탈)을 내려 목을 길게 하고 턱·입은 움직이지 않습니다(리뷰 두 번 지적 후 변경). 스펙 결정 표와 5절을 고쳤습니다.
- 두 어깨가 모두 보여야 체형으로 인정합니다. 다리 길게는 두 엉덩이와 발목 하나 이상이 있어야 하고 거꾸로·누운 사람은 건너뜁니다.
- 화면 이름 "전체 날씬"을 "몸 전체"로 부릅니다.
- 체형 분석 실패는 가져오기 경고에 넣지 않고 체형 도구 안내로만 보입니다.
- 수동 편집 잠금 문구를 얼굴형·체형 공통으로 바꿨습니다.
- 미리보기 캐시에서 밀려난 사진을 다시 준비하면 앱의 사진 정보(얼굴·인물·체형과 그 실패)도 새 분석으로 바꿉니다(D 최종 리뷰 이월).

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 전신 사진에서 Vision 관절 인식(자동 테스트에 전신 사진이 없음, 데모 셀카는 0명).
- 체형 7종의 느낌과 최대값이 과하거나 약한지.
- 팔이 몸에 붙은 자세·앉은 자세·옆모습·고개를 숙인 사람(목 보정이 턱 아래를 건드리는지).
- 여러 사람 사진에서 다리 띠가 다른 사람을 늘이는 정도.
- 다리 높이 배경 직선 휨과 다리 길게의 아래쪽 잘림.
- 배경 흐림과 함께 쓸 때 몸을 가늘게 하면 이미 흐린 배경이 몸 쪽으로 끌려 들어오는 모양.
- 상반신 사진에서 다리 길게 슬라이더가 켜져 있지만 효과가 없는 점이 혼란스러운지.
- iPhone·iPad 실기기와 시뮬레이터에서의 체형 분석 동작과 시간(앱 테스트는 스텁 관절만 씀).
- 48MP 원본 저장 속도와 메모리(다리 길게 포함).
- 체형 도구 화면: 슬라이더 7개 배치, 안내 문구, 꺼진 슬라이더.
- 실기기(iPhone·iPad)에서 위 항목 전부.

이전 절(D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

## 인물 보정 F 메이크업 (2026-10-15)

2026-10-15, 브랜치 `beauty-b-to-f` 커밋 `7d8ac3f` 기준(메이크업 도구와 드래그 중 슬라이더 수정 직후, 이 절을 쓰는 문서 커밋 바로 앞). Apple Silicon / macOS 26.6.2 / Xcode 27.0 / iOS 27.0 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5)). 이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다.

### 자동 검증

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**. 모듈 의존성·import 검사, `swift format lint --strict`, XcodeGen 2.46.0 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트까지 한 번에 통과했습니다.
- 패키지 `swift test` 331개 통과: MellowShared 43, MellowRendering 225, MellowLibrary 30, MellowExport 4, MellowEditing 29. 계획의 예상(322개, Rendering 216)보다 9개 많은 것은 E 마지막 수정의 렌더 테스트 3개와 구현 중 더한 테스트(감마 공간 섞기, 강도 0.5, 대상 얼굴, 같은 쪽 눈썹, 눈썹·쉐딩 캐시 항목, 눈썹·쉐딩 강도 0, 쉐딩 색상 유지) 때문입니다.
- 앱 XCTest(모두 위 실행 안에서): iPhone 18 Pro 시뮬레이터 67개, iPad Pro 13-inch (M5) 시뮬레이터 67개, macOS 68개 모두 통과. 계획의 예상(65·65·66)보다 2개씩 많은 것은 드래그 중 룩 적용과 드래그 중 슬라이더가 꺼지지 않는지 확인하는 테스트 2개 때문입니다.
- `./scripts/build-apple.sh ios-device`(커밋 `7d8ac3f`): 종료 코드 0. 서명 없는 Release iPhone/iPad arm64 빌드, Info.plist·PrivacyInfo 검사, 번들 ID·에셋 검사 통과.
- `./scripts/build-apple.sh mac`(커밋 `7d8ac3f`): 종료 코드 0. Release 빌드 arm64·x86_64, 서명 검사 통과.
- 두 빌드의 경고는 Core Image 커널 언어 API 지원 중단 경고뿐입니다(`WarpKernel.swift` 1곳, `SkinKernels.swift` 2곳, `FeatureKernels.swift` 2곳, `DisplacementWarp.swift` 3곳, E와 같음). 메이크업은 새 커널을 더하지 않아 새 경고가 없습니다. 빌드 로그에 "failed with exit code" 머리줄이 iPhone 빌드에 하나, Mac 빌드에 둘 있지만 빌드와 스크립트는 종료 코드 0입니다(E와 같음).
- 1.2.0 변경사항 `fastlane/release_notes/1.2.0.json`: 키는 `ko` 하나, 공백 아님, 392자(4,000자 이하). `/usr/bin/ruby fastlane/test/release_notes_test.rb` 6 runs, 0 failures, 0 errors.
- 실행 전후 새 SpringBoard 오류 보고서는 생기지 않았습니다(가장 최근 보고서가 실행 전과 같은 `SpringBoard-2026-10-15-180724.ips`). 테스트에 쓴 두 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5))는 실행 전 꺼져 있었고 실행 뒤에도 꺼진 상태였습니다. 실행 전부터 켜져 있던 다른 시뮬레이터(iPhone 17e)는 건드리지 않았습니다.

### 자동 테스트가 확인하는 것

- 카탈로그: 룩 5개·색 14개의 id와 순서, 색·강도 값 범위, 룩이 자기 부위 팔레트 색만 씀, 형식 위반(모르는 스키마 버전·부위, rgb 개수·범위, 부위를 넘는 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도) 거부, 앱 번들 사본이 `shared/makeup/makeup.v1.json`과 바이트 동일.
- 편집: 강도 0…1 클램프, 색을 처음 고를 때 강도 0이면 0.5, 눈썹·쉐딩 색 지정은 무시(단계 없음), 색을 빼도 강도 유지, 룩 적용은 실행 취소 한 단계이고 같은 룩을 다시 골라도 단계가 늘지 않음, 부위 변경 시 룩 이름이 풀림, 없음은 모두 지움, 수동 편집이 있어도 잠기지 않음.
- 렌더: 강도 0·얼굴 없음은 입력과 같은 바이트, 립·블러셔·아이섀도·눈썹·쉐딩/하이라이터가 각자 마스크 밖 바이트를 바꾸지 않음, 모르는 색·다른 부위 색·빈 카탈로그·특징점 없는 얼굴은 그 부위만 건너뜀, 범위 밖 강도는 자른 값과 같은 바이트, 강도 0.5는 입력과 강도 1 사이, 밝은 립(누드)이 입술을 어둡게 하지 않음(감마 공간 섞기), 쉐딩·하이라이터는 중간 톤 피부의 밝기만 바꾸고 색상각은 0.3° 미만 이동, 미리보기·저장 모두 파이프라인의 메이크업 카탈로그를 씀, 단계 순서.
- 마스크: 블러셔가 두 볼에 대칭으로 있고 눈·입·얼굴 밖은 0, 아이섀도가 눈꺼풀을 덮고 눈 안은 0, 30° 기울인 얼굴을 따라감, 아이섀도 띠는 같은 쪽 눈썹만 씀, 눈썹을 넓히고 원래 눈썹 상자에서 색을 잼, 쉐딩(광대 아래·턱선)과 하이라이터(콧대·이마·턱 끝) 위치, 특징점·눈·눈썹·코가 없으면 그 마스크 없음.
- 캐시: 상한이 얼굴 수에 비례, 얼굴 셋 × 두 해상도에서 모든 효과를 켜도 비우지 않음, 눈썹·쉐딩 마스크가 기존 캐시 항목을 함께 씀.
- 대상 얼굴: 고른 얼굴만 메이크업이 바뀌고 다른 얼굴은 한 픽셀도 안 바뀜, 범위 밖 번호는 입력과 같은 바이트.
- 앱: 메이크업 도구 순서, 룩 적용이 실행 취소 한 단위, 모르는 룩 무시, 없음, 수동 편집이 있어도 동작, 카탈로그가 없는 번들이면 nil과 안내 문구, 드래그 중 룩을 고르면 드래그가 먼저 끝남, 특징점 없는 얼굴 안내, 배경·체형 프리셋 값을 0으로 되돌릴 수 있음, 드래그 중에는 체형·배경 슬라이더가 꺼지지 않음.
- 시나리오(화면 없이 앱 모델로): 데모 사진 가져오기 → 피부 → 얼굴형 → 눈 → 배경 → 다리 길게 → 메이크업 데일리로 미리보기가 다시 바뀜 → 내보내기 파일이 정사각형. 얼굴·인물 마스크·관절점은 스텁입니다. iPhone·iPad 시뮬레이터에서도 통과했습니다.

이 테스트는 합성 얼굴과 스텁으로 돌며, 실제 사람에게 메이크업이 자연스러운지는 판단하지 않습니다.

### 스펙과 다르게 한 것

- 룩 적용을 편집 변경 항목 `EditChange.makeupLook` 대신 `EditDocument.applyMakeupLook` 한 경로로 했습니다(편집 규칙은 메이크업 목록을 몰라 룩 이름만으로 부위 값을 채울 수 없음). 스펙 결정 표와 1.2절을 고쳤습니다.
- 메이크업 데이터 파일을 읽을 때 형식 위반이 있으면 파일 전체를 거부합니다.
- 메이크업 섞기를 sRGB 감마 공간에서 합니다(선형 공간에서는 밝은 립이 입술을 어둡게 했음). 마스크 합성은 선형입니다. 스펙 결정 표와 6절을 고쳤습니다.
- 블러셔·쉐딩·하이라이터는 얼굴 좌표 타원 × 피부 다각형 비트맵입니다(별도 볼 다각형을 그리지 않음).
- 아이섀도는 흐린 눈꺼풀 띠에 흐리지 않은 눈 모양을 빼서 눈 안을 정확히 0으로 만들었습니다. 그 대신 속눈썹 선 경계가 딱 끊깁니다. 띠의 눈썹은 그 눈과 같은 쪽만 씁니다.
- 눈썹 진하게의 색은 원래 눈썹 상자 전체의 평균입니다.
- 다각형 비트맵 캐시 상한을 32 고정에서 얼굴 수 비례(얼굴당 16, 최소 32)로 바꿨습니다(실측 얼굴당 해상도마다 7개). 스펙 결정 표와 1.4절을 고쳤습니다.
- 색을 처음 고를 때 강도가 0이면 0.5로 둡니다. 룩 "없음"은 메이크업을 모두 지웁니다.
- 룩 칩에는 썸네일이 없습니다(이름만).
- 이월 정리: 대상 얼굴에 특징점이 없으면 뷰티·메이크업 패널에 안내를 보이고, 사람·관절이 없어도 프리셋으로 들어온 배경·체형 값은 0으로 되돌릴 수 있게 슬라이더를 켜며, 드래그 중에는 슬라이더를 끄지 않습니다.
- 상반신 사진의 다리 길게 안내는 바꾸지 않았습니다(슬라이더는 켜져 있고 효과 없음, E와 같음).

### 최종 리뷰 뒤 고친 것

- 얼굴 분석이 실패한 사진에서는 메이크업 룩·색·강도를 끄고 "없음"만 남깁니다(넣으면 저장이 실패했음). 이미 들어온 메이크업은 줄이거나 지울 수 있게 켜고, 드래그 중에는 끄지 않습니다. 얼굴이 없을 뿐인 사진은 저장이 되므로 그대로 켭니다.
- 슬라이더를 드래그하는 도중 도구를 바꾸면 드래그를 먼저 끝냅니다.
- 검증: 새 앱 테스트 3개 중 2개가 수정 전 실패, 수정 후 통과(얼굴 없음 테스트는 기존 동작 확인용). 패키지 `swift test` 331개, Mac 앱 테스트 71개 통과, `swift format lint --strict`, `./scripts/verify-modules.sh` 통과. iPhone·iPad 시뮬레이터 앱 테스트와 화면 확인은 하지 않았습니다.

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 인물 사진에서 메이크업 5룩과 14색의 느낌, 최대 강도가 과하거나 약한지.
- 어두운·밝은 입술에서 립 색이 바뀌는 정도.
- 앞머리·안경·머리카락이 볼이나 눈썹을 덮은 사진(블러셔·하이라이터·눈썹이 머리카락에 얹히는지).
- 얇은 눈썹에서 눈썹 진하게가 너무 약한지(상자 평균색이라 피부가 섞임).
- 아이섀도가 속눈썹 선에서 딱 끊기는 경계가 자연스러운지.
- 기울어진 얼굴, 옆으로 돌린 얼굴, 단체 사진.
- 메이크업 도구 화면: 룩 칩·5개 부위 탭·색 칩이 iPhone 폭에 들어가는지, 부위 탭 글자가 잘리지 않는지.
- 쉐딩 타원이 얼굴당 여러 개라 미리보기 지연이 느껴지는지.
- 48MP 원본 저장 속도와 메모리(메이크업 포함).
- 사람이 없는 사진에서 체형 슬라이더를 끌어 0을 지날 때의 모양.
- iPhone·iPad 실기기에서 위 항목 전부.

이전 절(E, D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

### 1.2.0 TestFlight에서 확인할 것 (B~F 통합)

- 실제 인물 사진과 전신 사진으로 피부 보정·자동 잡티, 얼굴형 10종, 눈·치아·입술, 배경 흐림 경계, 체형 7종, 메이크업 5룩을 보고 과하거나 약한 항목을 적습니다. 수치는 `RenderTuning`과 `shared/makeup/makeup.v1.json` 한 곳에서 조정합니다.
- 시뮬레이터·구형 기기에서 분석 실패 안내가 보이는지.
- 1.2.0 변경사항 문구(TestFlight "테스트할 내용"에 그대로 들어감)가 맞는지.

배포(`scripts/release.sh apple 1.2.0`, 태그 푸시)는 머지 뒤 별도로 실행하며 이 절을 쓸 때는 실행하지 않았습니다.

## TestFlight 전용 배포 경로 (2026-10-15)

- fastlane `beta` 레인(TestFlight 전용)과 배포 모드 변수 `IOS_RELEASE_MODE=testflight`는 2026-10-15 태그 `apple-v0.3.1`로 처음 실행해 통과했습니다(GitHub Actions run 38671616792, 0.3.1 빌드 1.1을 App Store Connect에 업로드). App Store 버전은 건드리지 않았습니다. 내부 테스터 기기에서 빌드가 보이는지는 확인하지 않았습니다.

## 인물 보정 G 피부 정밀·몸 피부·효과·작업 흐름 (2026-10-20)

2026-10-20, 브랜치 `beauty-g-evoto` 커밋 `909e156` 기준(분할 전후 비교 직후, 이 절을 쓰는 문서 커밋 바로 앞, 시나리오 테스트 확장은 이 문서 커밋에 함께 들어감). Apple M5 Pro / macOS 26.6.2 / Xcode 27.1 / iOS 27.0 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5)). 이 절의 검증은 모두 자동 테스트이며, 앱을 띄워 화면을 보거나 조작한 검증은 없습니다. Release 빌드(`build-apple.sh`)는 이번에 돌리지 않았습니다.

### 자동 검증

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**(시나리오 테스트 확장을 넣은 작업 트리에서 한 번 실행, 다시 돌리지 않음). 모듈 의존성·import 검사, `swift format lint --strict`(UI 테스트 폴더 포함), XcodeGen 재생성 후 xcodeproj 차이 없음, 패키지 테스트, iPhone·iPad 시뮬레이터 앱 테스트(병렬 테스트 끔), Mac 앱 테스트, iPhone UI 테스트까지 한 번에 통과했습니다.
- 패키지 `swift test` 380개 통과: MellowShared 49, MellowRendering 261, MellowLibrary 31, MellowExport 4, MellowEditing 35. G3 시작(G2 끝) 370개(Shared 47 · Rendering 256 · Library 30 · Export 4 · Editing 33)에서 효과 레시피 2, 효과 단계 5(글로우가 1 넘는 입력을 어둡게 하지 않는지 확인하는 수정 테스트 1 포함), 효과 편집 1, 선택 동기화 편집 1·라이브러리 1이 늘었습니다. G3 계획의 예상(377개, Rendering 257 · Editing 36)과 다른 것은 G2에서 렌더 테스트가 계획보다 3개 많았고(Rendering 256), G3에서 글로우 수정 테스트가 1개 늘었으며, 선택 동기화 편집 테스트가 계획의 2개가 아니라 1개로 들어갔기 때문입니다.
- 앱 XCTest(모두 위 실행 안에서): iPhone 18 Pro 시뮬레이터 77개, iPad Pro 13-inch (M5) 시뮬레이터 77개, macOS 78개 모두 통과(G3 시작 74개에서 효과 슬라이더 1, 동기화 메뉴 1, 분할 비교 1, 분할선 클램프 1이 늘어 계획과 같음). iPhone UI 테스트(`MellowPhotoUITests`) 2개 통과.
- 이 문서 커밋 전 Mac 앱 테스트를 따로 한 번 더 돌려 78개 통과를 확인했습니다(시나리오 확장 직후).
- 실행 전 켜진 시뮬레이터는 없었습니다. 실행 뒤 테스트에 쓴 두 시뮬레이터(iPhone 18 Pro, iPad Pro 13-inch (M5))는 꺼진 상태였고, 다른 시뮬레이터(iPhone 17e 등)는 건드리지 않았습니다. 실행 전후 SpringBoard 오류 보고서는 생기지 않았습니다.
- Mac 앱 테스트 로그에 `com.apple.linkd.autoShortcut` 연결 실패 줄이 찍히지만 테스트 결과와 무관합니다(테스트 호스트 앱의 시스템 서비스 연결 기록).

### 자동 테스트가 확인하는 것

- 레시피: 피부 정밀 7종·몸 피부 3종·효과 2종 키 왕복, 키가 없는 G 이전 세션·프리셋은 0으로 읽혀 결과가 같음, `hasEffect`·`dependsOnFaces`·`dependsOnPerson`(몸 피부는 인물만, 효과는 분석 불필요), 유한성 검사, 프리셋이 새 그룹을 나름, 스키마 키 집합(`testSkinRefinementKeysRoundTripAndDefaultToIdentity`, `testSkinRefinementScalarsAreCheckedForFinitenessAndCarriedByPresets`, `testBodySkinRoundTripsDefaultsAndDependsOnPerson`, `testBodySkinScalarsAreCheckedForFinitenessAndCarriedByPresets`, `testEffectsRoundTripDefaultsAndNeedNoAnalysis`, `testEffectScalarsAreCheckedForFinitenessAndCarriedByPresets`).
- 편집: 새 변경의 범위 클램프·잠기지 않음·실행 취소 한 단계, 자동 보정이 피부 정밀·몸 피부·효과를 지우지 않음, 선택 동기화가 고른 항목만 복사하고 얼굴 의존 항목이 없으면 대상 얼굴 유지·잠긴 사진의 얼굴형·체형 보존·빈 선택은 아무것도 안 함(`testSkinRefinementChangesClampAreNotLockedAndUndoOneStepEach`, `testApplyAutoKeepsSkinRefinements`, `testBodySkinChangesClampAreNotLockedAndAreCopiedByPresetsAndBatch`, `testApplyAutoKeepsBodySkin`, `testEffectChangesClampAreNotLockedAndAreCopiedButNotByAuto`, `testBatchCopiesOnlyChosenCategoriesAndKeepsTargetFaceWithoutFaceCategories`).
- 라이브러리: `applyToAll(from:categories:)`가 고른 항목만 다른 사진에 복사(`testApplyToAllWithCategoriesCopiesOnlyThose`).
- 주름 띠 마스크: 다크서클·팔자·마리오네트·미간 띠 위치, 기울어진 얼굴을 따라감, 특징점이 없는 띠만 빠짐(`testDarkCircleMaskSitsUnderBothEyesAndLeavesEyesAndCheeks`, `testNasolabialMaskRunsFromNoseWingToMouthCornerOnBothSides`, `testMarionetteMaskDropsFromTheMouthCornersTowardTheChin`, `testGlabellaMaskSitsBetweenTheBrows`, `testFoldMasksFollowARolledFace`, `testFoldMasksNeedTheirLandmarks`).
- 피부 정밀 렌더: 주름 4종이 자기 띠의 그늘만 올리고 그늘 없는 피부에 얼룩·색 기를 더하지 않으며 그늘의 채도를 지킴, 특징점 누락은 그 띠만 건너뜀, 얼룩 고르기는 얼룩을 펴고 모공을 남김, 번들거림은 밝은 피부 반점만 줄임, 붉은기는 볼보다 붉은 곳만 맑게 하고 혈색은 고르게 더함, 값 0은 같은 바이트이고 범위 밖 값은 자른 값과 같음, 상자만 있는 얼굴은 주름을 건너뛰고 얼룩 고르기는 동작, 고른 얼굴만 바뀜, `smoothing`만 있는 레시피는 G 이전 경로와 같은 바이트, 새 캐시 항목 없음(`testDarkCirclesLiftOnlyTheShadowUnderTheEyes`, `testNasolabialAndMarionetteLiftTheirOwnFoldOnly`, `testGlabellaLiftsBetweenTheBrowsOnly`, `testFoldLiftOnUnshadowedSkinAddsNoBlotchOrColorCast`, `testFoldLiftKeepsShadowChroma`, `testMissingLandmarksSkipOnlyThatFold`, `testToneEveningFlattensBlotchesAndKeepsPores`, `testShineMattifiesOnlyBrightSkinSpots`, `testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly`, `testZeroRefinementsAreIdentityAndOutOfRangeValuesRenderClamped`, `testBoxOnlyFaceSkipsFoldsButStillEvensTone`, `testTargetFaceRefinesOnlyThatFace`, `testSmoothingOnlyUsesTheLegacyBandMixPath`, `testRefinementsReuseTheSkinRasterAndAddNoCacheEntries`, `testScaledUnitSkinMaskMatchesStrengthMask`).
- 몸 피부 렌더: 값 0·사람 없음·얼굴 없음은 같은 바이트, 밝기는 보이는 피부만 올리고 셔츠·배경·눈은 그대로, 톤은 피부만 따뜻하게·차갑게, 매끄럽게는 얼굴을 빼고 몸 피부만, 범위 밖 값 클램프, 대상 얼굴과 무관하게 가장 큰 얼굴 기준, 눈·눈썹·입과 얼굴 전체 마스크가 사진당 캐시 항목 둘, `ToneShift.blueness`가 색차만 움직임(`testZeroValuesNoPersonOrNoFaceReturnInputBytes`, `testBrightnessLiftsVisibleSkinAndLeavesShirtBackgroundAndEyes`, `testToneWarmsOrCoolsSkinOnly`, `testSmoothingSkipsTheFaceAndSmoothsBodySkin`, `testOutOfRangeValuesRenderClamped`, `testBodySkinIgnoresTargetFaceAndUsesTheLargestFace`, `testBodySkinMasksAddTwoEntriesPerPhoto`, `testFeatureMaskCoversEyesBrowsAndLipsOfEveryFaceInOneRaster`, `testWholeFaceMaskCoversEveryFaceWithFeatureRingsInOneRaster`, `testToneShiftBluenessMovesOnlyChromaAndDefaultsToIdentity`).
- 효과 렌더: 값 0은 같은 바이트이고 범위 밖 값은 자른 값과 같음, 그레인은 두 번 렌더해도 같은 바이트이고 평균 밝기를 1바이트 안에서 유지, 글로우는 밝은 영역을 어두운 영역보다 더 올리고 1을 넘는 입력을 어둡게 하지 않음, 자르기·회전 뒤 extent를 따름(`testZeroEffectsReturnInputBytesAndOutOfRangeValuesClamp`, `testGrainIsDeterministicAndKeepsMeanBrightness`, `testGlowBrightensHighlightsMoreThanShadows`, `testGlowNeverDarkensValuesAboveOne`, `testEffectsFollowTheCurrentExtentAfterGeometry`). 단계 이름 배열과 캐시 상한은 `RenderPipelineTests`·`RegionMaskCacheTests`가 확인합니다.
- 앱: 뷰티 피부 탭 7개와 피부톤 탭 3개, 조정 패널 효과 2개가 각각 실행 취소 한 단계, 피부톤 슬라이더가 인물 분석 상태와 프리셋 값을 따름, 동기화 메뉴 선택과 적용, 분할 비교가 기존 전체 토글 옆의 모드이고 사진을 바꾸면 꺼짐, 분할선 위치 클램프(`testSkinTabEditsEveryRefinementKeyOneUndoStepEach`, `testSkinToneTabEditsEveryKeyOneUndoStepEachWhenPersonFound`, `testSkinToneSlidersFollowPersonAvailabilityAndPresetValues`, `testAdjustToolEditsEffectsOneUndoStepEach`, `testApplyToAllCopiesOnlyChosenCategories`, `testSplitCompareIsAModeBesideTheFullToggleAndResetsOnSelect`, `testFractionClampsToCanvasAndDefaultsWhenWidthIsZero`).
- 시나리오(화면 없이 앱 모델로, `testBeautySkinFaceFeaturesBackgroundBodyThenMakeupThenExportSucceeds`): 데모 사진 → 피부 보정 → 다크서클·얼룩 고르기 → 피부 밝기 → 그레인 0.5로 미리보기가 바뀜 → 전체 토글이 원본을 보임 → 분할 비교 켜고 끄기 → 얼굴형·눈·배경·다리·메이크업 → 색 온도 → 두 번째 사진을 가져와 색감만 동기화(두 번째 사진의 색감은 같고 피부·효과는 기본값) → 저장 파일이 정사각형. 얼굴·인물 마스크·관절점은 스텁입니다. 그레인을 켠 채 저장이 성공합니다.

이 테스트는 합성 얼굴·스텁 분석과 데모 사진으로 돌며, 실제 사람 사진에서 결과가 자연스러운지는 판단하지 않습니다.

### 구현 중 측정

- 몸 피부 매끄럽게 저장 시간(이 절을 쓰면서 잼, Mac): 데모 사진을 `sips -Z 8000`으로 키운 임시 8000×8000 PNG(64MP, 저장소에 넣지 않음)에 실제 Vision 얼굴·인물 분석으로 준비한 뒤 `PhotoPipeline.renderOriginal` + `makeCGImage`를 매끄럽게 1과 0으로 각각 3회 재어 중앙값을 냈습니다(데우기 1회 뒤, 커밋하지 않은 임시 XCTest). 두 번 돌린 결과는 0일 때 0.508초·0.502초, 1일 때 0.503초·0.542초로 차이가 0~0.04초이며 회차 간 흔들림과 같은 크기입니다. 매끄럽게 1은 바이트 27%를 바꿔 실제로 적용됐습니다. 시간은 PNG 읽기와 전체 렌더가 대부분입니다. iPhone·iPad 실기기, 48MP HEIC, 메모리 최고치는 재지 않았습니다.
- G2 구현 때(4000×3000 합성 피부 질감, 따뜻한 상태): 매끄럽게 1이 약 24ms 늘림(약 1.8배). 이번 절을 쓰면서 다시 재지 않았습니다.
- 그레인 평균 밝기: 중간 회색 단색에 그레인 1을 걸면 8비트 평균이 127.0 → 127.53(차이 0.53바이트, 문턱 ±1). G3 구현 때 잰 값이며 다시 재지 않았습니다.
- 주름 밝히기 판정 여유(G1 구현 때, 문턱 +12): 다크서클 +33·+19, 팔자 +18, 마리오네트 +16(표본 y 120), 미간 +25. 붉은기 맑게는 붉은 반점의 R−G 차이 −12(문턱 −10)로 여유가 얇습니다.
- 번들거림이 중주파도 줄인 뒤 반사광 감소량(G1 구현 때): 반지름 12px 반점 −29, 28px 반점 −16. 피부색에서 먼 흰 반사광 중심은 가중치 밖이라 거의 줄지 않습니다.

### 스펙과 다르게 한 것

모두 스펙 결정 표에 "(G1·G2·G3 구현 중 변경)"으로 적었고, 이 문서 커밋에서 몸 피부·글로우의 에이전트 참조 절을 결정 표에 맞췄습니다.

- 주름 국소 저주파 반지름 `foldLowBandFraction`을 0.04에서 0.015로 줄였습니다(0.04는 좁은 주름 그림자를 거의 지워 밝힘이 생기지 않음).
- 주름 밝히기를 채널별 차이 덧셈에서 BT.601 휘도 비율 곱셈으로 바꾸고 배율 상한 1.6(`foldLiftMaxGain`)과 휘도 분모 하한 0.01(`foldLumaFloor`)을 더했습니다(채널별 차이는 배경 옆 띠에 파란 기를 더했고, 같은 양을 더하면 다크서클이 회색으로 뜸).
- 번들거림은 저주파만이 아니라 번들거림 가중치만큼 중주파도 줄입니다(작은 반사광은 대부분 중주파에 있음).
- 몸 피부의 밝기·톤 제외 영역에 눈썹을 더했고(눈·입은 특징점이 없으면 대체 타원), 매끄럽게 제외 영역을 잘라내지 않은 얼굴 다각형 전체로 넓혔습니다(눈가·입가 고리가 두 번 매끄럽게 되고 눈썹이 하얗게 들리던 문제). 얼굴이 없으면 몸 피부는 그대로입니다(사용자 결정).
- 글로우는 `CIBloom` 대신 흐림 → 0…1로 자름 → 제곱 → 스크린 합성입니다(`CIBloom`은 고르게 밝은 영역을 밝히지 않았고, 자르지 않으면 1을 넘는 밝은 영역이 어두워짐).
- 선택 동기화는 9개 항목이고 선택은 저장하지 않습니다(스펙 그대로, 사용자 결정).
- 분할 비교는 기존 전체 토글을 그대로 둔 채 그 옆의 비교 모드로 더했습니다(스펙 그대로). 구현 중 자르기·회전을 바꾼 직후 원본과 미리보기의 비율이 잠시 다를 때 원본을 겹치지 않는 임시 방어 `AppModel.Policy.compareAspectTolerance`(0.01)를 더했습니다. 같은 비율의 기하 변경(좌우 반전, 180° 회전, 같은 비율 자르기)은 막지 못하므로 기하 일치 비교로 바꿀 후보입니다.

### 미검증 (사용자 확인 필요)

이번 작업에서 새로 생긴 항목:

- 실제 인물 사진에서 피부 정밀 7종(다크서클·팔자·마리오네트·미간·얼룩 고르기·붉은기·번들거림)의 느낌과 최대값이 과하거나 약한지.
- 주름 띠 위치, 특히 마리오네트(입꼬리 아래에 특징점이 없어 고정 각도)와 옆으로 돌린 얼굴.
- 하얗게 날아간 반사광(이마·코)에서 번들거림이 거의 줄지 않는 정도와 넓은 번들거림이 덜 줄어드는 정도.
- 몸 피부가 옷·배경·머리카락·다른 사람에게 번지는지, 얼굴과 몸에 조명이 다르게 떨어진 사진, 피부색이 다른 사람이 함께 있는 사진.
- 뒷모습·팔만 나온 사진에서 피부톤 탭이 얼굴 없음 안내만 보이는 것이 혼란스러운지.
- 그레인이 미리보기와 저장본에서 같은 모양으로 보이는지, 글로우의 느낌.
- iPhone 화면: 뷰티 › 피부 탭의 슬라이더 7개 배치, 뷰티 탭 4개(피부·얼굴·눈·입·피부톤) 글자가 잘리지 않는지, 동기화 항목 메뉴의 글자 폭.
- iOS에서 동기화 항목 메뉴가 항목을 하나 켜고 끌 때마다 닫히는지(여러 항목을 바꾸기 번거로움).
- 분할선 표시·손잡이 드래그 조작감(1×와 4× 확대, 자르기·회전한 사진), VoiceOver로 분할선 조절.
- 48MP 원본 저장 속도와 메모리(몸 피부 매끄럽게·글로우 포함).
- iPhone·iPad 실기기에서 위 항목 전부.

이전 절(F, E, D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

배포(릴리스 노트·태그·TestFlight)는 G 범위가 아니며 실행하지 않았습니다.
