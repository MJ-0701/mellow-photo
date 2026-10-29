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

항목마다 적어 둔 곳이 다릅니다.

- 스펙 결정 표에 "(G1·G2·G3 구현 중 변경)"으로 적은 것: 주름 밝히기 식, 번들거림의 중주파 감소, 몸 피부 제외 영역, 글로우. 몸 피부·글로우의 에이전트 참조 절은 `cea84ba` 문서 커밋에서 결정 표에 맞췄습니다.
- 스펙 1.6 상수 표에만 적은 것: 주름 국소 저주파 반지름 `foldLowBandFraction` 변경.
- 이 절에만 적은 것: 분할 비교 원본 겹침 규칙의 변경 경위와 보조 기술 조절 폭 `compareSplitAccessibilityStep`. 지금의 겹침 규칙 자체는 스펙 1.8 에이전트 참조에도 있습니다.

- 주름 국소 저주파 반지름 `foldLowBandFraction`을 0.04에서 0.015로 줄였습니다(0.04는 좁은 주름 그림자를 거의 지워 밝힘이 생기지 않음).
- 주름 밝히기를 채널별 차이 덧셈에서 BT.601 휘도 비율 곱셈으로 바꾸고 배율 상한 1.6(`foldLiftMaxGain`)과 휘도 분모 하한 0.01(`foldLumaFloor`)을 더했습니다(채널별 차이는 배경 옆 띠에 파란 기를 더했고, 같은 양을 더하면 다크서클이 회색으로 뜸).
- 번들거림은 저주파만이 아니라 번들거림 가중치만큼 중주파도 줄입니다(작은 반사광은 대부분 중주파에 있음).
- 몸 피부의 밝기·톤 제외 영역에 눈썹을 더했고(눈·입은 특징점이 없으면 대체 타원), 매끄럽게 제외 영역을 잘라내지 않은 얼굴 다각형 전체로 넓혔습니다(눈가·입가 고리가 두 번 매끄럽게 되고 눈썹이 하얗게 들리던 문제). 얼굴이 없으면 몸 피부는 그대로입니다(사용자 결정).
- 글로우는 `CIBloom` 대신 흐림 → 0…1로 자름 → 제곱 → 스크린 합성입니다(`CIBloom`은 고르게 밝은 영역을 밝히지 않았고, 자르지 않으면 1을 넘는 밝은 영역이 어두워짐).
- 선택 동기화는 9개 항목이고 선택은 저장하지 않습니다(스펙 그대로, 사용자 결정).
- 분할 비교는 기존 전체 토글을 그대로 둔 채 그 옆의 비교 모드로 더했습니다(스펙 그대로).
- 분할 비교의 원본 겹침: 구현 중에는 비율이 0.01 안으로 같을 때만 겹치는 임시 방어를 두었으나 같은 비율의 기하 변경(좌우 반전, 180° 회전, 같은 비율 자르기)을 막지 못했습니다. 최종 리뷰 수정에서 들고 있는 원본을 그린 기하가 보이는 미리보기를 그린 기하와 같을 때만 겹치는 규칙으로 바꾸고 비율 비교 상수는 없앴습니다. 원본 다시 그리기가 끝나기 전이나 실패한 뒤에는 겹치지 않습니다.
- 보조 기술(VoiceOver 등)로 분할선을 한 번 옮기는 폭 `AppModel.Policy.compareSplitAccessibilityStep`(0.1)을 더했습니다(스펙에 없던 상수).

### 최종 리뷰 수정 (2026-10-20)

브랜치 전체 리뷰에서 나온 항목을 고쳤습니다. 사용자에게 보이는 변화는 다음과 같습니다.

- 분할 비교는 원본을 미리보기와 같은 기하로 다시 그린 뒤에만 겹칩니다(좌우 반전·180° 회전 직후 뒤집히기 전 원본이 잠깐 겹치던 문제). 원본 다시 그리기가 실패하면 겹치지 않고 다음 렌더에서 다시 시도합니다.
- 분할선을 잡는 띠가 28pt에서 44pt로 넓어졌습니다(그린 손잡이 크기는 그대로).
- 바뀌는 값이 없는 동기화(잠긴 사진에 얼굴형만 복사 등)와 같은 프리셋 다시 고르기는 실행 취소 단계를 만들지 않고 다시 실행 기록도 지우지 않습니다. 바뀐 사진이 없는 전체 적용은 세션 파일을 쓰지 않습니다.
- 그레인 알갱이를 가장 가까운 화소로 키워 경계가 번지지 않습니다(알갱이 안이 한 값이 됨, 평균 밝기·결정성 테스트는 그대로 통과, 화면에서 어떻게 보이는지는 확인하지 않음).
- 특징점이 없는 얼굴의 안내 문구가 피부 보정·얼룩 고르기·붉은기·번들거림과 잡티·변형은 쓸 수 있고 주름 밝히기 4종은 특징점이 있어야 바뀐다고 알립니다.

자동 검증(이 절을 쓰기 전 코드 커밋 `984bba0`에 문서·주석 변경만 더한 작업 트리에서 한 번 실행):

- `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드 **0**(재시도 없이 한 번). 모듈 검사, lint, XcodeGen 차이 없음, 패키지, iPhone 18 Pro·iPad Pro 13-inch (M5) 시뮬레이터 앱 테스트, Mac 앱 테스트, iPhone UI 테스트가 모두 통과했습니다.
- 패키지 384개: MellowShared 49, MellowRendering 262, MellowLibrary 32, MellowExport 4, MellowEditing 37. 위 380개에서 그레인 알갱이 1, 바뀌는 값 없는 동기화·프리셋 1, 전부 동기화 누락 방지 1, 전체 적용 저장 생략 1이 늘었습니다.
- 앱: iPhone 18 Pro 78개, iPad Pro 13-inch (M5) 78개, macOS 79개, iPhone UI 테스트 2개 통과. 위 77·77·78개에서 분할 비교 원본 겹침 규칙 1이 늘었습니다.
- 고치기 전에 새 테스트가 실패하는 것을 확인했습니다: 동기화·프리셋(실패 3), 전체 적용 저장(실패 3), 그레인(64px 층에서 3787화소가 번짐), 분할 비교(실패 4), 안내 문구(얼룩 고르기 없음).
- 실행 전 켜진 시뮬레이터는 없었고 실행 뒤 두 시뮬레이터는 꺼진 상태였습니다. SpringBoard 오류 보고서는 생기지 않았습니다.
- 새 테스트 이름: `testSplitCompareShowsTheOriginalOnlyWhenItsGeometryMatchesThePreview`, `testNoOpBatchAndRepeatedPresetAddNoUndoStep`, `testBatchWithAllCategoriesCopiesEveryPresetGroup`, `testApplyToAllSkipsSavingWhenNothingChanged`, `testGrainLayerKeepsHardSquareGrains`.

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
- 여러 얼굴 + 모든 피부 슬라이더를 켠 48MP 저장 시간·메모리(얼굴마다 주름 띠 4개·대역 합성·붉은기를 따로 계산함).
- 분할선을 잡는 띠(44pt)가 iPhone 폭에서 옆 조작을 가리지 않는지.
- iPhone·iPad 실기기에서 위 항목 전부.

이전 절(F, E, D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다.

배포(릴리스 노트·태그·TestFlight)는 G 범위가 아니며 실행하지 않았습니다.

## 인물 보정 G4-1 주름 재설계·보이는 강도 (2026-10-20)

- 브랜치 `beauty-g4`(main `538a735`에서 분기), 코드 커밋 `c7b5c2c`와 최종 리뷰 수정(몸 피부 톤 0.035, 아래 "최종 리뷰 수정" 절)까지.
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- iOS 시뮬레이터 테스트와 실기기 검증은 하지 않았다.
- 로컬 시뮬레이터는 SpringBoard 오류 창 때문에 돌리지 않는 규칙이고, iOS는 CI 몫, 실기기는 사용자 조치다.
- iOS는 로컬에서 시뮬레이터용 빌드만(`generic/platform=iOS Simulator`, 기기 부팅 없음) 했다. `30dc671`에서 성공했고, 최종 리뷰 수정 작업 트리(`ad7e894` + 수정)에서 다시 성공했다(경고는 기존 `CIKernel(source:)` 지원 중단 8건과 AppIntents 메타데이터 안내 1건).
- 배포(릴리스 노트·태그·TestFlight)는 하지 않았다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 **0**(2026-10-20, 작업 트리 = `c7b5c2c`, 재시도 없이 한 번).
- 모듈 검사, lint, XcodeGen 차이 없음, 패키지, Mac 앱 테스트가 통과했다.
- iOS 시뮬레이터 앱 테스트·iPhone UI 테스트는 스크립트가 로컬에서 건너뛰었다.
- 패키지 **401**: MellowShared 49, MellowRendering 279(1 건너뜀: 치아 미백, 데모 사진이 다문 입), MellowLibrary 32, MellowExport 4, MellowEditing 37.
- G 기준 384에서 Rendering이 17 늘었다(실사진 수용 14, 주름 밝히기 2, 몸 피부 대체 영역 1).
- Mac 앱 **83**. 시작 전 실측 80에서 진단 1, 사진을 바꾸면 렌더 오류 지움 1, 진단의 수동 편집 개수 줄 1이 늘었다.
- 상태 줄 테스트는 기존 테스트를 고친 것이라 수가 늘지 않았다.
- CI: GitHub Actions "Apple checks" 실행 `39402590661`(`30dc671`, macos-15·Xcode 26.3)은 **성공**했다(2026-10-20 10:02 UTC 완료, `gh run view`로 확인).
- 그 실행에서 패키지 401(1 건너뜀: 치아 미백)이 통과했고 실사진 수용 테스트도 macOS Vision에서 통과했다.
- iOS 시뮬레이터(컨트롤러 전달: iOS 18.5) 앱 테스트 두 기기 각 81, Mac 앱 82, iPhone UI 테스트, 서명 없는 Release 빌드도 통과했다.
- 그 실행에는 측정 출력 줄(`c7b5c2c`)이 없어 CI의 실측값(여유가 좁은 값 포함)은 남지 않았다.
- `907d667`·`c7b5c2c`·`b33b569`와 최종 리뷰 수정 커밋은 다음 실행 `39405911176`(`9f77057`)이 확인했고 **성공**했다(2026-10-20, `gh run view`로 확인).

### 실측 표 (데모 사진, 실제 Vision, 폰 화면 배율 가로 1170px, 값 1 또는 끝값)

측정값은 이번 실행의 `acceptance <항목> <지표>=<값>` 출력 줄이다.
"바꾸기 전"은 Tasks 1–4 구현 보고의 Task 1 커밋 시점 측정이다(상수·띠를 바꾸기 전 코드).
"(상한)"은 자연스러움 상한(스펙 1.4)이고 나머지는 보이는 강도 하한(스펙 1.2)이다.

| 항목 | 측정 | 문턱 | 바꾸기 전 | 측정값 | 바꾼 것 |
|---|---|---|---|---|---|
| 피부 보정 1 | 얼굴 상자 바뀐 비율 | ≥ 0.04 | 0.305 | 0.305 | 없음 |
| | 피부 마스크 fine 분산 비 (상한) | ≥ 0.85 | — | **0.882** | 없음 |
| 얼룩 고르기 1 | 얼굴 상자 바뀐 비율 | ≥ 0.04 | 0.380 | 0.380 | 없음 |
| | 피부 가중 평균 \|ΔY\| | ≥ 3 | 6.65 | 6.65 | |
| | 피부 가중 평균 ΔY (상한) | ≤ 7.65 | 4.35 | +4.35 | |
| | 피부 마스크 fine 분산 비 (상한) | ≥ 0.85 | — | 1.006 | |
| 다크서클 1 | 얼굴 상자 바뀐 비율 | ≥ 0.010 | 0.0006 | 0.0243 | 띠 위치·크기, 주름용 피부 비트맵, 피부 가중 주변 기준, `foldSurroundFraction` 0.12 → 0.18 |
| | 띠 가중 평균 ΔY | ≥ 3, ≤ 20.4 (상한) | 0.66 | +9.37 | |
| | 띠 가중 색차 (상한) | ≤ 0.01 | — | 0.0047 | |
| | 띠 가중 fine 분산 비 (상한) | ≥ 0.85 | — | 1.374 | |
| | 합성 그늘 회복 | ≥ 0.5 | 0.506 | 1.349 | |
| 팔자 1 | 얼굴 상자 바뀐 비율 | ≥ 0.005 | 0.0009 | 0.0173 | 위와 같음 |
| | 띠 ΔY · 색차 · 질감 비 (상한) | ≤ 20.4 · ≤ 0.01 · ≥ 0.85 | — | +5.41 · 0.0025 · 1.242 | |
| | 합성 그늘 회복 | ≥ 0.5 | 0.380 | 1.162 | |
| 마리오네트 1 | 띠 ΔY · 색차 · 질감 비 (상한) | 같음 | — | +3.37 · 0.0016 · 1.228 | 위와 같음 |
| | 합성 그늘 회복 | ≥ 0.5 | 0.027 | 0.856 | |
| 미간 1 | 띠 ΔY · 색차 · 질감 비 (상한) | 같음 | — | +2.23 · 0.0009 · 1.076 | 위와 같음 |
| | 합성 그늘 회복 | ≥ 0.5 | 0.073 | 0.791 | |
| 붉은기 −1 | 합성 반점 Cr 초과분 제거율 | ≥ 0.5 | 0.373 | 0.640 | `rednessClearMax` 0.7 → 1.0, `rednessReferenceOffset` 0.01 신설 |
| | 심은 반점 \|ΔCr\| | > 0.02 | 0.062 | 0.062 | |
| 붉은기 +1 | 피부 가중 평균 ΔR | ≥ 5 | 7.42 | +14.9 | `rednessFlushMax` 0.03 → 0.06 |
| 번들거림 1 | 합성 반사광 감소율 | ≥ 0.4 | 0.482 | 0.543 | `shineLumaOffset` 0.12 → 0.08, `shineLumaRamp` 0.1 → 0.08 |
| | 심은 반사광 ΔY | > 10 | 28.0 | 28.0 | |
| 몸 피부 밝기 1 | 전체 바뀐 비율 | ≥ 0.15 | 0.509 | 0.509 | 없음 |
| | 몸 피부 영역 평균 ΔY (상한) | ≤ 25.5 | — | +18.3 | |
| 몸 피부 톤 +1 | 피부 가중 (ΔR − ΔB) | ≥ 6 | 19.8 | 28.7 | `bodySkinToneMax` 0.025 → 0.035(처음 0.05에서 40.6, 최종 리뷰로 내림) |
| 몸 피부 톤 ±1 | 피부 가중 \|ΔR − ΔB\| (상한, 최종 리뷰 추가) | ≤ 30 | — | +1: 28.7 · −1: 28.7 | |
| 바디 매끄럽게 1 | 전체 바뀐 비율 | ≥ 0.10 | 0.189 | 0.189 | 없음 |
| 그레인 1 | 전체 ΔY 표준편차 | ≥ 5 | 5.58 | 14.5 | `grainMaxAmplitude` 0.12 → 0.30 |
| | 알갱이 한 변(화면 px) | ≥ 2.5 | 1.40 | 2.93 | `grainSizeFraction` 0.0012 → 0.0025 |
| 글로우 1 | 전체 바뀐 비율 | ≥ 0.40 | 0.885 | 0.885 | 없음 |
| 눈 또렷하게 1 | 눈 마스크 가중 평균 \|ΔY\| | ≥ 3 | 2.41 | **3.20** | `eyeWhiteLift` 0.2 → 0.3, `eyeIrisSharpen` 0.8 → 1.0 |
| 입술 생기 1 | 입술 마스크 가중 \|ΔCr\| | ≥ 0.02 | (\|ΔY\| 0.22, 지표 변경) | 0.047 | 지표만 바꿈(상수 그대로) |
| 치아 미백 1 | — | — | — | 건너뜀(다문 입) | — |
| 블러셔 복숭아 1 | 블러셔 마스크 가중 평균 \|ΔY\| | ≥ 3 | 6.42 | 6.42 | 없음 |
| 피부 8종 동시 | 얼굴 다각형을 얼굴 폭 5% 넓힌 영역 밖 바뀐 비율 (상한) | ≤ 0.002 | 0.0000 | 0.0000 | — |
| 원터치 행 | 스펙 1.2·1.4의 원터치 행 | — | — | 재지 않음(G4-2 범위) | — |

여유가 좁은 값은 세 개이고 CI의 Xcode·macOS Vision 차이로 뒤집힐 수 있다.
- 피부 보정 질감 비 0.882(문턱 0.85, 여유 0.03).
- 눈 또렷하게 3.20(문턱 3.0, 여유 0.20).
- 몸 피부 톤 상한 28.7(문턱 30, 여유 1.3/255).

문턱 수치는 하나도 바꾸지 않았다.
입술 생기의 지표 변경은 컨트롤러 판정이고 스펙 1.2와 결정 표에 적었다.
몸 피부 톤 상한 30/255는 최종 리뷰 뒤 컨트롤러 판정으로 새로 더한 문턱이고 스펙 1.4와 결정 표에 적었다.

### 자동 테스트가 확인하는 것

- `RealPhotoAcceptanceTests`(14): `testSkinSmoothingChangesTheFaceButKeepsPores`, `testToneEveningEvensSkinButKeepsPores`, `testDarkCirclesLiftUnderTheEyesVisiblyAndNaturally`, `testNasolabialLiftsTheFoldVisiblyAndNaturally`, `testMarionetteRecoversASyntheticShadow`, `testGlabellaRecoversASyntheticShadow`, `testRednessClearsASyntheticBlotchAndFlushIsVisible`, `testShineFlattensASyntheticHighlight`, `testBodySkinBrightnessToneAndSmoothingAreVisible`, `testGrainIsVisibleAtPhoneScale`, `testGlowIsVisibleAtPhoneScale`, `testEyeAndLipFeaturesAreVisible`, `testBlushIsVisible`, `testFaceItemsLeaveHairAndBackgroundUntouched`.
- 데모 사진 준비(실제 Vision 얼굴 1개)가 실패하면 수용 테스트마다 오류로 실패하고 다른 테스트는 계속 돈다.
- `testBodySkinBrightnessToneAndSmoothingAreVisible`는 인물 마스크가 없어도 건너뛰지 않는다(몸 피부 단계와 측정 영역이 함께 얼굴 둘레 대체 영역을 쓴다). 어느 영역이었는지는 `acceptance bodySkin personMask=` 줄로 남는다.
- 주름 띠와 캐시: `FoldRegionsTests`(새 표본 점, 입꼬리 옆까지 이어지는 팔자 띠, 아래 띠), `RegionMaskCacheTests.testRefinementsUseOneSkinRasterAndOneFoldRaster`와 캐시 수 40·60.
- 주름 밝히기: `SkinStageTests.testFoldLiftOnUnshadowedSkinAddsNoBlotchOrColorCast`(다시 정의), `testFoldLiftWithTooLittleSurroundSkinLeavesTheBandUnchanged`, `testFoldLiftIgnoresDarkFeaturesInTheSurround`.
- 붉은기: `SkinStageTests.testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly`(볼 기대값을 기준 여유만큼 이동, 창백한 조각은 그대로).
- 몸 피부 대체 영역: `BodySkinStageTests.testBodySkinFallsBackToTheFaceNeighbourhoodWithoutAPersonMask`.
- 피부톤 상태 줄·슬라이더: `AppModelTests.testSkinToneStatusLineReflectsPersonAndFaceConditions`.
- 진단: `AppModelTests.testDiagnosticLinesListBuildPhotoAnalysisAndNonDefaultRecipeKeys`, `testLastRenderFailureClearsWhenTheSelectedPhotoChanges`, `testDiagnosticRecipeSummaryCollapsesLocalEditsIntoOneCountLine`.

### 스펙과 다르게 한 것

앞의 일곱은 G4 스펙 결정 표에 "(G4-1 구현 중 변경)"으로 적었고, 표본 점은 스펙 2.1, 진단 줄은 스펙 6에 적었다.

- 눈 또렷하게 상수 `eyeWhiteLift` 0.2 → 0.3, `eyeIrisSharpen` 0.8 → 1.0(스펙 1.2의 조정 후보 안).
- 입술 생기 하한을 휘도 대신 입술 마스크 가중 |ΔCr| ≥ 0.02로 잰다(입술 커널은 휘도를 바꾸지 않는다).
- G1 단위 테스트 `testFoldLiftOnUnshadowedSkinAddsNoBlotchOrColorCast`를 띠 안 색차 ≤ 0.01, 띠 안 평균 ΔY ≤ +0.08, 띠 밖 1바이트 이내로 다시 정의했다.
- 사람 분석이 실패해도 얼굴이 있으면 몸 피부 슬라이더를 켠다(렌더가 대체 영역으로 실제 적용한다).
- 합성 반사광 도우미가 아무것도 심지 못하던 버그를 고쳤다(고친 뒤 +28/255).
- "띠 밖·마스크 밖 불변"은 채널 차이 1바이트 이내로 단언한다(섞기 반올림, G4 전에도 같음).
- 몸 피부 톤 상수는 스펙 처음 값 0.05가 아니라 0.035이고 상한 \|ΔR − ΔB\| ≤ 30/255를 더했다(최종 리뷰, 자연스러움 우선).
- 합성 얼굴 표본 점 몇 개를 격자로 확정한 자리로 옮겼다(스펙 2.1에 값과 이유, 문턱은 그대로).
- 진단은 수동 편집(`operations`)을 점·획마다 적지 않고 `operations=N` 한 줄로 적는다(스펙 6의 "스크린샷 한 장" 목적).

### 최종 리뷰 수정 (2026-10-20)

브랜치 전체 리뷰(Important 2·3, Minor 7·10)를 반영했다. 스펙을 먼저 고친 문서 커밋 `ad7e894` 뒤에 코드를 고쳤다.

- 몸 피부 톤 `bodySkinToneMax` 0.05 → 0.035. 0.025도 하한의 3.3배였고 0.05는 얼굴 전체가 주황빛으로 뜰 위험이 있었다.
- 자연스러움 상한 "피부 톤(몸) ±1: 피부 가중 \|ΔR − ΔB\| ≤ 30/255"를 스펙 1.4와 수용 테스트(`Naturalness.bodyToneMaximumRedMinusBlue`)에 더했다. 하한 6/255 단언은 그대로다.
- 몸 피부 수용 테스트의 "인물 마스크 없으면 건너뜀"을 없앴다. CI Vision이 사람을 못 찾으면 이제 건너뛰지 않고 대체 영역으로 잰다.
- 로컬에서 인물 마스크를 임시로 nil로 바꿔 대체 영역 경로를 한 번 돌렸다(커밋하지 않음): 밝기 바뀐 비율 0.673, 몸 피부 평균 ΔY +15.8, 톤 +1 26.1 · −1 −26.2, 매끄럽게 바뀐 비율 0.269로 모두 통과.
- `docs/architecture/modules.md` 테스트 열을 지금 테스트에 맞췄다(얼굴 없으면 항등, 인물 마스크 없으면 얼굴 둘레 대체 영역).
- 스펙 1.2의 다크서클 fine 분산 비를 1.4·테스트와 같은 0.85로 맞췄다.

자동 검증(최종 리뷰 수정 작업 트리에서 한 번 실행, 재시도 없음):

- `./scripts/test-apple.sh` 종료 코드 **0**. 모듈 검사, lint, XcodeGen 차이 없음, 패키지, Mac 앱 테스트가 통과했고 iOS 시뮬레이터 앱 테스트·iPhone UI 테스트는 스크립트가 로컬에서 건너뛰었다.
- 패키지 **401**(MellowShared 49, MellowRendering 279(1 건너뜀: 치아 미백), MellowLibrary 32, MellowExport 4, MellowEditing 37), Mac 앱 **83**. 테스트 수는 늘지 않았다(기존 몸 피부 수용 테스트에 단언을 더함).
- `./scripts/verify-modules.sh` 통과, `swift format lint --strict` 출력 없음, iOS 시뮬레이터용 빌드 성공(부팅 없음).
- 이 수정은 CI 실행 `39405911176`(`9f77057`)에서 **성공**했다.

### 미검증 (사용자 확인 필요)

- iPhone 화면과 저장본에서 그레인 1이 보이는지, 저장본에서 거칠지 않은지.
- iPhone 화면에서 다크서클·팔자·마리오네트·미간 1이 보이는지, 다크서클이 과하지 않은지(띠 평균 +9.4/255, Evoto +5.6).
- 몸 피부 밝기 1과 톤 ±1의 느낌. 톤 +1은 R − B 28.7/255(1.3.0의 약 1.4배)이고 상한 30/255 테스트가 있다. 기기에서 약하면 상한 안에서만 올린다.
- 붉은기 −1에서 볼의 붉은 기 변화가 기준 아래로 모두 눌려 평평해 보이는지.
- 주름 미리보기 지연. 주름마다 얼굴 폭 18% 흐림을 두 번(분자·분모) 돌린다.
- 사람 영역이 없을 때 대체 영역(얼굴 상자 가로 3배·아래 4배)이 피부색 배경을 밝히는지.
- 피부톤 탭 상태 줄과 정보 시트 "진단" 절의 iPhone 폭 표시, 진단 스크린샷 한 장, "복사" 버튼(눌러도 표시가 없다).
- iOS 진단 분기(`uname` 기기 모델, 시뮬레이터 식별자, `UIPasteboard`)는 시뮬레이터용 빌드만 했고 실행하지 않았다.
- 커플·단체 사진에서의 2차 측정(H3 Task 1 사진을 들인 뒤, G4-2).
- CI의 iOS 시뮬레이터 앱 테스트와 UI 테스트.
- 실사진 수용 문턱이 CI(Xcode 26.3)의 Vision에서도 넘는지, 특히 여유가 좁은 두 값.

이전 절(G 이전)의 미검증 항목은 그대로 승계한다.

## 인물 보정 H 사람별·성별 그룹 보정 (2026-10-20)

- 브랜치 `beauty-g4`, H 커밋은 `5895ba8`(생성 사진 테스트 지원)부터 이 절의 문서 커밋까지다.
- H1·H2·H3은 G4-2·G4-3과 같은 브랜치에서 섞여 진행됐다(실행 순서는 G4 스펙 5절).
- 검증 작업 트리는 `4e08045`에 두 시나리오 테스트와 `TestSupport.makeModel`의 얼굴 분석기 인자 타입 변경만 더한 상태다(문서 변경 전).
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- 이 절의 검증은 모두 자동 테스트이며, 앱을 띄워 화면을 보거나 조작한 검증은 없다.
- iOS 시뮬레이터 테스트와 실기기 검증은 하지 않았다(로컬 시뮬레이터 금지 규칙). iOS는 CI 몫이고 실기기는 사용자 조치다.
- 배포(릴리스 노트·태그·TestFlight)는 H 범위가 아니며 실행하지 않았다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 **0**(2026-10-20, 위 작업 트리, 재시도 없이 한 번).
- 모듈 검사, `swift format lint --strict`, XcodeGen 재생성 뒤 xcodeproj 차이 없음, 패키지, Mac 앱 테스트가 통과했다.
- iOS 시뮬레이터 앱 테스트와 iPhone UI 테스트는 스크립트가 로컬에서 건너뛰었다(`MELLOW_IOS_TESTS`를 켜지 않음).
- 패키지 **454**: MellowShared 69, MellowRendering 292(1 건너뜀: 치아 미백, 데모 사진이 다문 입), MellowLibrary 34, MellowExport 4, MellowEditing 55.
- Mac 앱 **99**(`TEST SUCCEEDED`).
- H 시작 기준(`0cd2380`)은 패키지 401(Shared 49, Rendering 279, Library 32, Export 4, Editing 37), Mac 83이었다.
- 늘어난 패키지 53 중 H가 39(H1 16, H2 20, H3 3)이고 G4-2·G4-3이 14다.
- 늘어난 Mac 16 중 H가 11(H3 Task 2 5, Task 3 2, 리뷰 반영 3, Task 4 시나리오 1)이고 G4-3이 5다.
- 이 문서 커밋 전에 iOS 시뮬레이터용 빌드만 한 번 했다(`generic/platform=iOS Simulator`, 기기 부팅 없음, `BUILD SUCCEEDED`).
- CI(Xcode 26.3)는 컨트롤러가 확인하고 결과는 머지 기록에 남긴다. 이 절을 쓸 때 확인한 상태는 아래 G4 절의 "CI 상태"에 함께 적었다.

### 자동 테스트가 확인하는 것

- 레시피 층: 성긴 층은 덮어쓴 키만 쓰고 왕복, 사람 기록의 관대한 읽기(빠진 층은 빈 층, 모르는 성별은 미지정, 깨진 기록만 버림), 빈 그룹 층 정리, 유한성 검사, 프리셋은 그룹 층만, 스키마(`testLayerEncodesOnlyOverriddenKeysAndRoundTrips`, `testLayerAppliesRemovesAndDiffs`, `testPeopleRoundTripAndDefaultToEmpty`, `testPeopleScalarsAreCheckedForFinitenessAndPresetsCarryGroupsOnly`, `testPruneDropsEmptyGroupLayersSoTheRecipeStaysDefault`, `testPersonRecordsDecodeLenientlyAndOnlyBrokenRecordsAreDropped`, `testPeopleSchemaDescribesLayersGroupsAndRecords`, `testPresetPeopleGroupsPersistAndIndividualsAreDropped`).
- 옛 세션 이행: `targetFace`가 개인 층(`legacyIndex`)으로 옮겨지고 범위 밖·손상 인덱스는 짝이 없으며 `PortraitAdjustments`에는 더 없음(`testLegacyTargetFaceMigratesIntoAPersonRecord`, `testPortraitAdjustmentsNoLongerCarryATargetFace`, `testLegacyIDNeverCrashesOnOutOfRangeIndices`).
- 해석: 전체 → 그룹 → 개인을 키 단위로 겹침, 미지정은 그룹을 건너뜀, 수동 성별이 추정을 이김, 겹친 값의 룩 이름(`testLayersOverlayKeyByKeyAndUndeterminedGenderSkipsGroups`, `testScopeResolutionEffectiveGenderAndOverriddenKeys`, `testLookIDComesFromTheTopLayerThatOverridesMakeup`).
- 짝짓기: 인덱스가 밀려도 같은 사람, 멀거나 크기가 다른 얼굴은 짝 없음, 1:1·결정적·`legacyIndex` 폴백, 겹친 얼굴에서 편집과 렌더가 같은 사람을 고름, 같은 id 기록은 앞의 것만(`testAnchorsSurviveIndexShiftsAndRejectFarOrOddSizedFaces`, `testMatchingIsOneToOneDeterministicAndFallsBackToLegacyIndex`, `testPersonForFaceFollowsTheGlobalMatchForOverlappingFaces`, `testDuplicateIDsKeepOnlyTheFirstRecord`).
- 층 편집: 대상 층에만 쓰고 클램프, 얼굴을 처음 만지면 기록을 만들고 빈 기록은 지움, 성별 지정은 잠금 대상이고 사람이 필요, 상속으로 재설정과 잠금, 잠긴 사진의 연결·삭제는 그 사람의 수동 성별 그룹 얼굴형까지 봄, 연결·삭제·legacy 연결·대상 룩이 실행 취소 한 단계, 겹친 얼굴 편집이 렌더 짝짓기를 따름, 기록 없는 얼굴의 룩, legacy 연결은 대체 짝인 기록만(`testScopedSetWritesOnlyThatLayerAndClamps`, `testFirstTouchOfAFaceCreatesTheRecordAndEmptyRecordsArePruned`, `testGenderAssignmentIsLockedByLocalEditsAndNeedsAPerson`, `testLocalEditLocksFaceShapeAndGender`, `testResetOverridesRestoresInheritanceAndRespectsLock`, `testRebindAndRemoveOnALockedPhotoRespectTheGenderGroupFaceShape`, `testRebindRemoveBindLegacyAndScopedLookAreOneUndoStep`, `testFaceEditsFollowTheRenderPairingForOverlappingFaces`, `testLookForAFaceWithoutARecordCreatesItInOneStep`, `testBindLegacyPeopleFillsOnlyRecordsPairedThroughTheirIndex`).
- 프리셋·동기화: 프리셋은 개인 층·성별을 두고 그룹 층을 바꿈, 동기화는 그룹 층을 복사하고 받는 사진에서 그 항목의 개인 키를 지움, 얼굴 의존 항목이 없으면 개인 층 유지, 라이브러리 전체 적용(`testPresetKeepsIndividualsAndGenderButReplacesGroups`, `testBatchSyncCopiesGroupsAndClearsIndividualKeysOfSyncedCategories`, `testBatchCopiesOnlyChosenCategoriesAndKeepsIndividualsWithoutFaceCategories`, `testApplyToAllCarriesGroupLayersNotIndividuals`, `testSavedPresetCarriesGroupLayersNotIndividuals`).
- 렌더(합성 얼굴): 얼굴마다 해석한 값, 개인 층은 그 얼굴만, 그룹 층은 그 성별 얼굴만(피부·메이크업), 개인 얼굴형은 그 얼굴의 원소만, 겹친 얼굴의 짝짓기가 편집과 같음, 옛 `targetFace` 렌더가 그 얼굴만(`testFaceTargetsResolvePeopleLayersPerFace`, `testIndividualLayerSmoothsOnlyThatFace`, `testGenderGroupPaintsOnlyFacesOfThatGender`, `testIndividualFaceShapeMakesPrimitivesOnlyForThatFace`, `testOverlappingFacesUseTheSameGlobalPairingAsEditing`, `testTargetFaceLimitsPortraitStagesToOneFace`).
- 성별 추정 포트(구현 없음): 신뢰도 0.75·얼굴 폭 5%·yaw 0.6rad 임계값, 실패·길이 불일치는 조용히 미지정, 추정이 그룹 층을 고르되 수동 지정이 이김(`testGenderEstimatesAreThresholdedAndFailuresAreSilent`, `testEstimatedGenderSelectsGroupLayerUnlessManuallyAssigned`).
- 앱: 칩 목록(추정·지정·미지정·찾지 못함·덮어쓴 수), 성별·재설정의 대상 라우팅과 실행 취소 한 단계, 캔버스 탭(겹친 얼굴은 작은 상자, 얼굴 밖은 전체, 드래그는 무시, 렌더 중에도 대상 선택), 준비 때 legacy 기록 연결(체크포인트 없음), 찾지 못한 기록의 연결·삭제와 기록 없는 얼굴의 룩, 잠긴 사진에서 얼굴형을 다른 얼굴로 옮기는 편집 거절, 대상별 패널 값과 덮어쓴 키, 사라진 대상은 전체로 읽음, 성별 바꾸기·대상 기억·원터치 드래그·연결 가드, 칩 제목·기호(`testPersonChipsReflectEstimatesManualGenderAndOverrides`, `testGenderAndResetAreRoutedToTheCurrentTargetAndUndoOneStep`, `testCanvasTapSelectsTheFaceAndLegacyPeopleAreBoundOnPrepare`, `testUnmatchedPersonCanBeReboundOrRemovedAndLookAppliesToAFace`, `testLockedPhotoRefusesEditsThatMoveFaceShapeOntoAnotherFace`, `testScopedPanelValuesShowInheritedAndOverriddenKeysPerTarget`, `testTargetTapIgnoresDragsAndIsNotBlockedByRendering`, `testStaleTargetFallsBackToAll`, `testGenderChangesTargetMemoryOneTouchDragUndoAndRebindGuard`, `testChipTitlesAndSymbolsFollowGenderSourceAndMatching`).
- 생성 사진 세트: 테스트 타깃 사본이 공유 원본과 같은 바이트이고 라벨이 모든 사진을 기술, Vision 얼굴 수가 라벨 인원과 같음(`couple-01`·`group-01`만, `testPeopleFixturesMatchSharedCopiesAndLabelsDescribeEveryPhoto`, `testVisionFindsTheLabelledNumberOfFaces`).
- 시나리오(`testCoupleFixtureManualGenderGroupAndIndividualThenSyncAndExport`, 실제 Vision): `couple-01`·`group-01`을 가져와 커플 얼굴 2개를 라벨대로 남·여로 지정 → 칩 성별이 라벨과 같음 → 여성 그룹 피부 보정 0.8로 미리보기가 바뀜 → 남성 얼굴은 그 값을 받지 않고 여성 얼굴은 받음 → 여성 얼굴 폭 −0.3이 그 사람 층의 덮어쓴 키 하나 → 피부만 동기화하면 단체 사진은 여성 그룹 층만 받고 개인 기록·성별 지정은 받지 않음 → 단체 사진 얼굴 5개가 모두 미지정 → 커플 사진 저장 성공.
- 이 시나리오 테스트는 처음 실행부터 통과했다. 이미 구현된 동작을 묶는 테스트라 실패하는 모습을 따로 보지 않았다.

이 테스트들은 합성 얼굴·스텁 분석·생성 사진으로 돌며, 실제 사람 사진에서 결과가 자연스러운지는 판단하지 않는다.

### 옛 세션 이행

- `targetFace`가 있던 사진은 읽을 때 전체 층이 비고 그 인덱스 사람의 개인 층(`legacyIndex`)으로 값이 옮겨진다. 그래서 "전체" 칩에서는 값이 0으로 보이고 "사람 i" 칩에서 값이 보인다. 레시피 단위는 `testLegacyTargetFaceMigratesIntoAPersonRecord`가 확인한다. 화면에서 칩 값을 보는 확인은 하지 않았다.
- 렌더 바이트: H2 Task 5 구현 때 이행 전 커밋(`bd17370`)과 이행 뒤 트리에서 같은 임시 테스트로 옛 레시피 네 개(`targetFace 0` 피부 0.5, `targetFace 1`에 피부·자동 잡티·다크서클·얼굴 폭·눈·입술·립·눈썹·노출, 범위 밖 `targetFace 7`, B0 옛 키 `skinSmoothing`·`faceSlim`)를 렌더해 이어 붙인 4 MB가 `cmp`로 같았다. 임시 테스트는 커밋하지 않았고 이 절을 쓰면서 다시 재지 않았다.
- 커밋된 테스트 `testTargetFaceLimitsPortraitStagesToOneFace`는 옛 JSON(`targetFace 1`)을 디코드한 렌더가 그 얼굴에만 건 렌더와 같은 바이트이고 모든 얼굴에 건 렌더와 다른지 매번 확인한다.
- 준비 뒤 legacy 기록에는 anchor가 채워지고 실행 취소 단계는 생기지 않는다(`testCanvasTapSelectsTheFaceAndLegacyPeopleAreBoundOnPrepare`).

### 생성 사진 세트

- 다섯 장, 모두 1024×1024 JPEG, 합계 1 823 297바이트(약 1.8 MB, 한도 5 MB), 장당 최대 466 KB(한도 600 KB).
- 위치는 `shared/fixtures/people/`이고 출처·생성 도구·사용 조건은 같은 폴더 `README.md`에 있다. 사용 조건(OpenAI 이용 약관) 최종 확인은 사용자 조치다.
- 테스트 타깃 사본은 `apple/Tests/MellowRenderingTests/Fixtures/people/`의 `couple-01`·`group-01`과 `labels.json`이다.
- 눈 확인(H3 Task 1, 생성 때): 다섯 장 모두 인원·성별이 라벨과 같고 손·얼굴 왜곡·글자·워터마크가 없었다. 재생성은 0회였다.
- Vision 얼굴 수는 이 절을 쓰면서 macOS `VNDetectFaceLandmarksRequest`(앱의 `VisionFaceAnalyzer`와 같은 요청)로 다섯 장 모두 다시 셌다(임시 스크립트, 커밋하지 않음). 자동 테스트는 두 장만 단언한다.

| 사진 | 크기 | 라벨 인원(왼쪽부터) | Vision 얼굴 수 | 특이점 |
|---|---|---|---|---|
| `couple-01.jpg` | 380 KB | 2(남·여) | 2 | 정면 성인, 실내. 자동 테스트 |
| `couple-02.jpg` | 313 KB | 2(남·여) | 2 | 남 안경, 여 약 45° 돌림, 역광 |
| `group-01.jpg` | 306 KB | 5(여·남·여·남·여) | 5 | 피부톤 다양, 노년 1, 모두 정면. 자동 테스트 |
| `group-02.jpg` | 466 KB | 6(남·여·남·여·남·여) | 6 | 손으로 볼 가림 1, 옆얼굴 1 |
| `group-03.jpg` | 315 KB | 4(여·남·여·남) | 4 | 안경 1, 다른 사람 뒤 일부 가림 1 |

### 스펙과 다르게 한 것

H 스펙 결정 표와 본문에 "(H1·H2·H3 구현 중 변경)"으로 먼저 적고 고쳤다.

- 얼굴 → 사람은 anchor 하나에 가장 가까운 기록이 아니라 렌더와 같은 전역 1:1 짝짓기로 정한다. 그래서 `set(_:forPersonAt:)` 대신 `set(_:forFace:of:)`, `applyMakeupLook(_:forFace:of:)`이고 `personID(at:)`는 없다(`peopleByFace`·`personID(forFace:of:)`).
- `prune()`은 빈 기록과 함께 빈 그룹 층도 지운다(기본 레시피 판정과 체크포인트 비교가 흔들리지 않게).
- 사람 기록은 관대하게 읽고 같은 id는 앞의 것만 남긴다. 옛 인덱스는 `PersonID.legacyIndexRange` 안으로 모은다.
- `PortraitResolver.resolve`는 `gender:` 대신 `estimate:`를 받고 수동 지정 우선을 안에서 정한다.
- `PortraitScope`는 MellowEditing이 아니라 MellowShared에 있다(해석·편집·앱이 함께 쓴다).
- 전체 층 재설정의 잠금은 "얼굴형 키가 들어 있으면"이 아니라 "0이 아닌 얼굴형을 실제로 되돌릴 때"다. 사람 삭제·연결의 잠금은 그 기록 층과 기록의 수동 성별 그룹 층의 얼굴형을 함께 본다.
- 잠긴 사진에서 기록을 지우거나 옮기는 편집이 짝을 바꿔 어느 얼굴의 얼굴형 값이라도 달라지게 하면 앱이 거절한다. 이 가드는 `AppModel`에 있고 다른 사진으로의 동기화는 검사하지 않는다.
- legacy 기록의 anchor는 지금 짝짓기에서 그 인덱스로 짝이 된 기록에만 채운다.
- 겹친 값의 메이크업 룩 이름은 메이크업 부위를 덮어쓴 가장 위 층의 것이다.
- 자동 보정은 얼굴이 있으면 원터치를 포함해 그룹 층도 다시 쓴다(G4 질문 2 판정, 결정 표 "(G4 변경)" 행).
- 캔버스 대상 탭은 뷰티·메이크업 도구에서 탭만 받는 제스처이고(확대한 사진의 한 손가락 이동은 스크롤 뷰가 받음), 누른 점과 뗀 점이 `AppModel.Policy.targetTapTolerance`(0.02)보다 멀면 무시하며, 렌더 중에도 대상을 고른다.
- 성별 메뉴는 칩의 컨텍스트 메뉴와 함께 선택된 사람 칩 아래 "성별: 미지정 ⌄" 글자 단추로 연다(처음 계획의 "…" 단추 대신).
- 뷰티 패널의 대상 안내(점 설명)는 "세부 조정" 안 맨 위에 있다.
- 시나리오 테스트는 계획의 `FakeImporter(staged:)` 대신 받은 파일 그대로 가져오기(`passesThroughFileURLs`)를 쓰고, 실제 Vision을 넘기려고 `TestSupport.makeModel`의 얼굴 분석기 인자를 `any FaceAnalyzer`로 넓혔다. 여성 그룹 피부 보정은 0.8, 얼굴 폭은 여성 얼굴이다(스펙 2절의 "0.5·사람 1"과 값만 다름).

### 미검증 (사용자 확인 필요)

- 실제 커플·단체 사진에서 사람 칩, 성별 지정, 그룹 값, 개인 값, 재설정, 동기화 결과.
- iPhone 폭에서 칩 줄의 가로 스크롤과 사람 칩 컨텍스트 메뉴(길게 누르기), "성별: … ⌄" 글자 단추.
- 성별 단추의 44pt 누름 영역(음수 여백으로 줄 높이에 넣지 않음)이 iOS에서 실제로 위아래 14pt까지 먹는지.
- 빈 컨텍스트 메뉴가 붙은 슬라이더 제목 줄을 길게 누를 때 들림·햅틱이 생기는지.
- 대상 칩 높이 30pt가 44pt 권고보다 작아 누르기 어려운지(계획 결정).
- 캔버스 탭 정확도(겹친 얼굴, 작은 얼굴), 확대한 뷰티·메이크업 캔버스에서 한 손가락 이동이 그대로 되는지.
- 렌더 중 캔버스 탭: 미리보기 기하가 레시피보다 늦은 순간(자르기 실행 취소 직후 등)의 탭이 다른 얼굴을 고르지 않는지.
- 원터치 뒤 그룹 층이 이긴다는 것: "전체"에서 바꾼 피부·눈입과 나중에 "전체"에 건 메이크업 룩이 성별을 지정한 사람에게는 안 보이는 것이 혼란스러운지.
- 자동 성별 추정은 H4 전까지 "없음"이다. 모든 사람이 미지정으로 시작한다. 추정 배지는 만들었지만 보일 일이 없다.
- 옛 세션을 연 사진에서 "전체" 칩 값이 0으로 보이는 것이 혼란스러운지.
- CI의 iOS 시뮬레이터 앱 테스트·UI 테스트(Xcode 26.3).
- iPhone·iPad 실기기에서 위 항목 전부.

이전 절의 미검증 항목은 그대로 승계한다.

## 인물 보정 G4 원터치 (2026-10-20)

- 브랜치 `beauty-g4`, G4-2(`c2def19`부터)와 G4-3(`2646cf6`부터)의 커밋과 이 절의 문서 커밋까지다.
- 검증 작업 트리는 `4e08045`에 시나리오 테스트(이 절의 원터치 시나리오와 H 커플 시나리오)와 `TestSupport.makeModel`의 얼굴 분석기 인자 타입 변경만 더한 상태다(문서 변경 전).
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- 이 절의 검증은 모두 자동 테스트이며, 앱을 띄워 화면을 보거나 조작한 검증은 없다.
- iOS 시뮬레이터·실기기는 하지 않았다(로컬 시뮬레이터 금지 규칙, iOS는 CI 몫, 실기기는 사용자 조치).
- 배포(릴리스 노트·태그·TestFlight)는 하지 않았다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 **0**. 패키지 **454**(MellowShared 69, MellowRendering 292(1 건너뜀: 치아 미백), MellowLibrary 34, MellowExport 4, MellowEditing 55), Mac 앱 **99**.
- G4가 더한 테스트는 패키지 14(G4-2 13: Shared 3 · Editing 6 · Rendering 4, G4-3 리뷰 반영 Editing 1)와 Mac 5(G4-3 Task 1 3, Task 2 1, Task 3 시나리오 1)다. 나머지 증분은 H다.
- iOS 시뮬레이터용 빌드만 성공했다(`generic/platform=iOS Simulator`, 부팅 없음).
- Xcode 26.3 타입 검사 시간 초과(CI 실행 `39422792756`, `bd573ce`)는 `807f874`에서 긴 섞인 덧셈 사슬을 나눠 고쳤다. 로컬 Xcode는 27.1뿐이라 26.3 컴파일은 CI로만 확인된다.

### 원터치 실측 (실제 Vision, 폰 화면 배율 가로 1170px)

이번 실행의 `acceptance oneTouch-…` 출력 줄이다. G4-2 구현 보고의 값과 모두 같다.

데모 사진(`demo-portrait.png`), 하한(얼굴만, 몸 피부 없음):

| 항목 | 문턱 | 측정값 |
|---|---|---|
| 여성 0.6 얼굴 상자 바뀐 비율 | ≥ 0.05 | 0.1526 |
| 남성 0.6 얼굴 상자 바뀐 비율 | ≥ 0.05 | 0.0825 |
| 공통 0.6 얼굴 상자 바뀐 비율 | ≥ 0.05 | 0.1139 |
| 여성 1 얼굴 상자 바뀐 비율 | ≥ 0.10 | 0.2717 |
| 남성 1 얼굴 상자 바뀐 비율 | ≥ 0.06 | 0.1420 |
| 여성 1 대 남성 1 차이 | ≥ 0.02 | 0.1012 |
| 남성 1 입술 색차 | ≤ 0.01 | 0.0000 |

데모 사진, 상한(몸 피부를 포함한 전체 대상 결과, 몸 피부 밝기 표 값 0.15):

| 경우 | 피부 평균 ΔY(/255, 0.6만 1.275~12.75) | 질감(fine 분산) 비(0.6 ≥ 0.9, 1 ≥ 0.85) | 99백분위 \|ΔY\|(≤ 60) | 피부 색차(≤ 0.015) | 눈썹 바뀐 비율(≤ 0.05) | 얼굴·몸 피부 밖(≤ 0.002) | 얼굴만 렌더의 얼굴 밖, 뺌 없음(≤ 0.002) | 입술 색차(여 ≤ 0.03, 그 외 ≤ 0.01) |
|---|---|---|---|---|---|---|---|---|
| 여성 0.6 | 2.385 | 0.956 | 20.0 | 0.0020 | 0.0000 | 0.0000 | 0.0000 | 0.0053 |
| 남성 0.6 | 1.794 | 0.965 | 12.8 | 0.0019 | 0.0000 | 0.0000 | 0.0000 | 0.0003 |
| 공통 0.6 | 2.057 | 0.960 | 16.2 | 0.0021 | 0.0000 | 0.0000 | 0.0000 | 0.0003 |
| 여성 1 | — | 0.930 | 30.7 | 0.0031 | 0.0280 | 0.0000 | 0.0000 | 0.0092 |
| 남성 1 | — | 0.947 | 20.4 | 0.0031 | 0.0280 | 0.0000 | 0.0000 | 0.0004 |
| 공통 1 | — | 0.939 | 25.4 | 0.0032 | 0.0280 | 0.0000 | 0.0000 | 0.0004 |

커플 사진(`couple-01.jpg`, 라벨대로 남·여 지정, 전체 원터치 1, 몸 피부 없음):

| 항목 | 문턱 | 측정값 |
|---|---|---|
| 남성 얼굴 상자 바뀐 비율 | ≥ 0.03 | 0.1868 |
| 여성 얼굴 상자 바뀐 비율 | ≥ 0.03, 남성보다 큼 | 0.3895 |
| 남성 입술 색차 | ≤ 0.01 | 0.0000 |
| 미지정 두 얼굴(공통 표) | ≥ 0.03 | 0.2893 · 0.3165 |

- 상한에 걸려 내린 표 값은 하나다: 몸 피부 밝기 0.2 → 0.15(강도 1에서 눈썹 바뀐 비율 9.1%가 상한 5%를 넘음). 눈썹 여유는 2.2%p다.
- 남성 기본 0.6 얼굴 상자 바뀐 비율의 여유는 0.0325다.
- 얼굴 표만으로는 기본 0.6 피부 평균 ΔY가 0.24~0.81/255라 하한 1.275/255에 못 미친다(G4-2 리뷰 측정). 하한 1.275는 전체 대상이 쓰는 몸 피부 밝기로 넘는다. 그래서 그룹·사람 대상 원터치(몸 피부를 쓰지 않음)는 같은 사람에게서 "전체"보다 흐리게 보인다.
- 문턱 수치는 하나도 바꾸지 않았다.

### 자동 버튼 결정 (질문 2)

- 판정: 포함(`AppModel.Policy.autoIncludesOneTouch` = true).
- 자동은 색감·디테일 자동과, 얼굴이 있으면 원터치 기본 강도 0.6(전체 대상: 전체 층 공통 표, 남성·여성 그룹 층 각 성별 표, 몸 피부 밝기)을 체크포인트 하나로 쓴다. 얼굴이 없으면 색감·디테일만이다.
- 대가: 색감만 맞추려던 사용자도 피부·눈입·블러셔·립이 바뀌고, 그룹 층에서 손으로 바꾼 묶인 키가 성별 표 값으로 덮인다(실행 취소 한 번으로 되돌림).
- 테스트: `testAutoEnhanceIncludesOneTouchOnlyWhenFacesExist`(앱), `testApplyAutoCanIncludeOneTouchInOneStep`(편집 규칙). 상수 하나를 끄면 분리로 돌아간다.

### 자동 테스트가 확인하는 것

- 표: 강도 선형 곱·0…1 자름·상한, 남성 블러셔·립 없음, 얼굴형 없음, 표시 키 왕복과 렌더 무관, 프리셋 표시 운반과 옛 파일 이행(`testTablesScaleLinearlyAndNeverTouchShapeOrLipColour`, `testOneTouchMarkRoundTripsAndIsNotARenderValue`, `testPresetValuesCarryOneTouchMarksAndLegacyMigrationDropsThem`).
- 편집 규칙: 층별 표 쓰기와 강도, 그룹·사람은 그 성별 표만, 손으로 묶인 키를 바꾸면 그 층의 표시만 지움, 프리셋은 표시를 나르고 동기화는 네 항목을 모두 복사할 때만 표시를 복사, 자동에 원터치 포함, 몸 피부 밝기는 전체 층 표시에 묶이고 톤은 쓰지 않음, 메이크업이 그대로면 룩 이름 유지(`testOneTouchWritesTablesPerLayerAndStrengthScales`, `testOneTouchOnGroupAndPersonUsesThatGenderTableOnly`, `testManualChangeOfABundledKeyClearsOnlyThatLayerMark`, `testPresetsCarryMarksAndSyncCopiesThemOnlyWithAllThreeCategories`, `testApplyAutoCanIncludeOneTouchInOneStep`, `testOneTouchBundlesBodyBrightnessIntoTheAllMarkButLeavesBodyTone`, `testAllLayerOneTouchKeepsTheLookWhenMakeupIsUnchanged`).
- 실사진 수용: 위 실측 표(`testOneTouchIsVisibleForEachGenderAndDiffersBetweenThem`, `testOneTouchStaysNaturalAtDefaultAndMaximum`, `testOneTouchNeverReshapesTheFaceOrBody`, `testOneTouchOnTheCouplePhotoTreatsMaleAndFemaleDifferently`).
- 앱: 원터치가 현재 대상으로 가고 강도를 기억, 버튼이 열린 드래그를 끝내고 손상 표시는 슬라이더용으로 자름, 사람 대상은 몸 피부를 쓰지 않음, 자동은 얼굴이 있을 때만 원터치 포함, 강도 글자와 대상별 안내(`testOneTouchRoutesToTheCurrentTargetAndRemembersStrength`, `testOneTouchButtonEndsAnOpenDragAndStrengthIsClampedForTheSlider`, `testAutoEnhanceIncludesOneTouchOnlyWhenFacesExist`, `testStrengthTextAndHintsFollowTheTarget`).
- 시나리오(`testOneTouchThenStrengthThenDetailOverrideThenExportSucceeds`, 데모 사진 + 스텁 얼굴): 원터치 버튼 → 강도 0.6 표시와 꼬리표 → 강도 슬라이더 1로 미리보기가 바뀜 → "세부 조정"에서 다크서클을 바꾸면 전체 층 표시·꼬리표가 사라지고 여성 그룹 표시는 남음 → 실행 취소 한 번에 표시 1이 돌아옴 → 저장 성공, 오류 없음. 처음 실행부터 통과했다(이미 구현된 동작을 묶는 테스트).

### 스펙과 다르게 한 것

G4 스펙 결정 표와 본문에 "(G4-2·G4-3 구현 중 변경)"으로 먼저 적고 고쳤다.

- 몸 피부 밝기 표 값 0.2 → 0.15.
- 실사진 수용은 하한을 얼굴만, 상한을 몸 피부를 포함한 전체 대상 결과로 잰다. 얼굴 밖 상한은 얼굴만 렌더에서 뺌 없이도 잰다.
- 몸 피부 밝기는 전체 층 표시에 묶이고 몸 피부 톤은 표 값이 0인 동안 쓰지 않는다.
- 표시 규칙 셋을 더했다: 수동 성별 변경은 그 사람 층 표시를 지움, 층 전체 재설정은 표시도 지움, 룩 이름은 블러셔·립이 실제로 바뀔 때만 지움.
- 동기화는 피부·눈입·메이크업·몸 피부 네 항목을 모두 복사할 때만 표시를 복사한다(처음 계획은 세 항목).
- 기본 강도 0.6은 `OneTouchBundle.defaultStrength`(Shared)에 두고 `EditingPolicy.oneTouchDefaultStrength`가 내보낸다.
- 강도 슬라이더 값은 손상 파일의 표시도 0…1로 자른다.
- 원터치 안내 문구는 그룹 값이 메이크업(립·블러셔)까지 "전체"보다 앞선다는 것과 그룹·사람 원터치가 몸 피부를 바꾸지 않는다는 것을 말하고, iPhone 조절 영역(200pt)에 맞게 전체 두 줄·그룹·사람 한 줄로 줄였다.
- 원터치 줄은 `ViewThatFits` 없이 늘 한 줄이다(드래그 중 배치가 바뀌면 슬라이더가 다시 만들어짐). 버튼 기호는 iOS 18·macOS 15 전에는 `wand.and.stars`다.

### 미검증 (사용자 확인 필요)

- 실제 얼굴에서 원터치의 자연스러움: 남성은 절제되고(덜 매끄럽게, 블러셔·립 없음) 여성은 블러셔·입술 생기가 은은한지. 표 값 취향.
- 성별 칩·사람 칩의 원터치는 몸 피부를 쓰지 않아 같은 사람에게서 "전체"보다 흐리게 보이는 것이 혼란스러운지.
- 원터치 뒤 그룹 층 값(립·블러셔 포함)이 나중에 "전체"에 건 메이크업 룩과 피부·눈입 변경을 성별을 지정한 사람에게서 가리는 것.
- 강도 슬라이더 드래그 감, "—" 표시, "세부 조정" 접기와 꼬리표.
- iPhone 조절 영역(200pt)에서 칩·원터치 줄·"세부 조정" 머리가 스크롤 없이 보이는지. 미지정 사람 대상은 어림 약 193pt로 여유가 몇 pt뿐이다. 큰 글자 크기(Dynamic Type)와 iPhone SE 폭(전체 안내가 세 줄이 될 수 있음).
- 손쉬운 사용 큰 글자 크기에서 고정 폭 원터치 버튼이 강도 슬라이더를 거의 없애는지.
- `List` 밖 "세부 조정" 머리 글자를 눌러 접고 펴지는지(iOS).
- 원터치 버튼(`.borderedProminent`, 강조색 위 `Theme.canvas` 글자)의 라이트·다크 대비, macOS가 글자색을 무시하는지.
- 렌더 중 캔버스 탭으로 대상을 고르는 감(H 절의 같은 항목).
- 원터치·자동을 쓴 저장본이 미리보기와 같은지.
- 실측은 데모 한 장과 커플 한 장이다. 다른 피부톤·조명은 재지 않았다.
- G4-1 절의 미검증 항목(그레인·주름 4종·몸 피부 밝기·톤·붉은기·진단 절 등)은 1.3.1이 TestFlight에 올라가 있으나 기기 확인 결과를 아직 받지 않았다.

### CI 상태

- 컨트롤러가 CI로 확인하고 결과는 머지 기록에 남긴다. 이 절은 CI 통과를 주장하지 않는다.
- 이 절을 쓰며 한 번 확인한 상태(2026-10-20 13:02 UTC, `gh run view`): GitHub Actions "Apple checks" 실행 `39425146910`(`4e08045`, 수동 실행)은 **진행 중**이었고 결과(conclusion)는 아직 없었다.
- 그 실행은 이 절의 두 시나리오 테스트와 문서 커밋을 포함하지 않는다. 그 뒤 커밋은 다음 CI 실행이 확인한다.
- 그 실행은 다음 실행에 밀려 취소됐다.
- 실행 `39428823603`(`2f6d704`)은 **실패**했다. iPhone 16 Pro 시뮬레이터(iOS 18.5) 앱 테스트 `EditorScenarioTests`의 두 번째 사진 뒤 첫 사진 다시 고르기 대기(10초)가 넘쳤다.
- 원인은 사진을 바꿀 때 취소된 미리보기 렌더가 다시 준비를 기다린 뒤에도 끝까지 렌더한 것이었다(기능 회귀 아님, macOS에서 렌더 시간은 `9f77057`과 같음).
- `1c20182`에서 준비와 렌더 사이에 취소를 확인해 건너뛰게 고쳤고 시간 한도는 늘리지 않았다.
- 실행 `39433933844`(`1c20182`, macos-15·Xcode 26.3, 패키지·Mac·iPhone·iPad 시뮬레이터 앱 테스트·UI 테스트)은 **성공**했다(2026-10-20, `gh run view`로 확인).
- CI의 iPhone 앱 테스트 묶음 시간은 82개 107.6초에서 98개 205초로 늘었다. 지켜볼 항목이다.
- 바로 앞 실행 `39422792756`(`bd573ce`)은 Xcode 26.3 타입 검사 시간 초과로 실패했고 `807f874`가 고쳤다.

이전 절의 미검증 항목은 그대로 승계한다.

## 인물 보정 I 이중턱·부유방·사람별 체형 (2026-10-21)

- 브랜치 `beauty-body`, 기준 `main` `8accbf6`(1.4.0)에서 `6a8e5af`(설계)부터 이 절의 문서 커밋까지다.
- 검증 작업 트리는 최종 리뷰 수정 커밋 `80abddf`이고 그 뒤에는 이 절만 바뀌었다(앞선 실행은 `d0cd92d`·`20c621e`, 세 번 모두 종료 코드 0).
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- 이 절의 검증은 모두 자동 테스트다. 앱을 띄워 화면을 보거나 조작한 검증은 없다.
- iOS 시뮬레이터·실기기는 하지 않았다(로컬 시뮬레이터 금지 규칙, iOS는 CI 몫, 실기기는 사용자 조치).
- 배포(태그·TestFlight)는 하지 않았다. 다음 버전 변경사항 파일 `fastlane/release_notes/1.5.0.json`만 썼고 버전은 올리지 않았다.

### 자동 검증

- `./scripts/test-apple.sh` 종료 코드 **0**(2026-10-21, 위 작업 트리 `80abddf`).
- 모듈 검사, `swift format lint --strict`, XcodeGen 재생성 뒤 xcodeproj 차이 없음, 패키지, Mac 앱 테스트가 통과했다.
- iOS 시뮬레이터 앱 테스트는 스크립트가 로컬에서 건너뛰었다("iOS 시뮬레이터 앱 테스트 생략", `MELLOW_IOS_TESTS`를 켜지 않음).
- 패키지 **545**: MellowShared 80, MellowRendering 365(1 건너뜀: 치아 미백, 데모 사진이 다문 입), MellowLibrary 34, MellowExport 4, MellowEditing 62.
- Mac 앱 **111**(`TEST SUCCEEDED`).
- 변경사항 파일 검사 `/usr/bin/ruby fastlane/test/release_notes_test.rb` 6개 통과.

### 수용 실측 (`ShapeAcceptanceTests`, 생성 사진, 실제 Vision, 폰 px = 사진 폭을 1170px로 줄인 픽셀)

사진은 앱과 같은 사진 준비(얼굴·인물·관절·인스턴스 분석)를 거치고, 이동은 렌더가 쓰는 것과 같은 이동량 지도에서, 밝기·배경·남녀 규칙은 렌더 픽셀에서 잰다.

| 항목 | 사진 | 하한 | 측정 | 상한 |
|---|---|---|---|---|
| 이중턱 턱밑 띠 최대 위쪽 이동 | chin-01 | 3 폰 px | 18.74 폰 px | — |
| 이중턱 최대 이동 / 얼굴 폭 | chin-01 | — | 0.0394 | 0.045 |
| 이중턱 턱선·턱 끝 이동 | chin-01 | — | 0.0001 폰 px | 0.5 폰 px |
| 이중턱 입술 이동 | chin-01 | — | 0.0000 px | 0(0.05 px) |
| 턱밑 그늘 띠 평균 밝기 증가 | chin-01 | — | 9.78 / 255 | 12 / 255 |
| 부유방 옆선 이동(두 쪽) | torso-01 | 2 폰 px | 10.13 · 10.12 폰 px | 어깨 폭 × 0.035 (측정 0.030 · 0.030) |
| 부유방 팔 영역 이동 / 옆가슴 이동 | torso-01 | — | 0.000 | 0.15 |
| 허리 −1·부유방 1 함께: 부유방 · 허리 이동 | torso-01 | 2 폰 px | 10.13 · 10.12 · 20.26 · 20.26 | — |
| 허리 −1·부유방 1 함께: 팔 영역 / 몸통 윤곽 최대 | torso-01 | — | 0.000 | 0.15 |
| 허리 ±1 | torso-01 | 2 폰 px | 20.26 | — |
| 몸 전체 ±1 | torso-01 | 2 폰 px | 11.82 | — |
| 팔 ±1 | torso-01 | 2 폰 px | 3.81 | — |
| 허벅지 ±1 | torso-01 | 2 폰 px | 건너뜀(무릎 관절 없음) | — |
| 어깨 ±1 | torso-01 | 2 폰 px | 13.50 | — |
| 목 ±1 | torso-01 | 2 폰 px | 10.13 | — |
| 격자선 휨: 체형 전 항목 −1 · +1 · 이중턱 1 (가장자리 선 포함) | torso-01 격자 합성 | — | 0.000 · 0.000 · 0.000 px (59,172 · 59,172 · 77,736곳) | 0.5 px(미리보기) |
| 대조: 같은 묶음을 보호 없이 그렸을 때 띠 안 격자선 휨 −1 · +1 · 이중턱 | torso-01 격자 합성 | 하나라도 0.5 px 초과 | 3.54 · 3.17 · 0.00 px | — |
| 실루엣 띠 밖 배경 변화: −1 · +1 · 이중턱 | lines-01 | — | 0.00% · 0.00% · 0.00% | 0.2% |
| 전체 층·남성 그룹 부유방 1 | couple-body-01 | — | 기본 렌더와 같은 바이트 | 같은 바이트 |
| 여성 그룹 부유방 1: 남성 인스턴스 안 변화 | couple-body-01 | — | 0.00% | 0.2% |
| 여성 그룹 부유방 1: 여성 옆선 이동(두 쪽) | couple-body-01 | 2 폰 px | 7.99 · 7.93 | — |
| 여성 그룹 부유방 1: 여성 팔 영역 / 옆가슴 이동 | couple-body-01 | — | 0.000 | 0.15 |
| 남성 개인 층 부유방 1: 남성 옆선 이동 | couple-body-01 | 2 폰 px | 10.66(한쪽, 다른 쪽은 옆선 점 없음) | — |
| 남성 개인 층 부유방 1: 남성 팔 영역 / 옆가슴 이동 | couple-body-01 | — | 0.000 | 0.15 |
| 여성 개인 층 허리 −1: 여성 허리 이동 · 남성 인스턴스 안 변화 | couple-body-01 | 2 폰 px · — | 15.98 · 15.97 · 0.00% | — · 0.2% |

- 미리보기 렌더 시간(단언 없음, 체형 전 항목 −1·이중턱 1, 1024px, 이 Mac): torso-01 처음 0.009초·다시 0.004초, couple-body-01 처음 0.021초·다시 0.004초. 커널 컴파일과 Core Image 캐시가 들어간 값이라 기기 시간이 아니다.
- 원본 해상도 렌더 시간(단언 없음, torso-01을 8000×6000으로 늘리고 허리 −1·이중턱 1, 보호 묶음 2개, 최대 이동 138.5px, 이 Mac GPU, 5번 실행의 중앙값): 보호 지도만 그리기 0.014초 → 0.013초, 렌더 전체(처음) 0.161초 → 0.144초, 렌더 전체(다시) 0.160초 → 0.134초, 보정 없는 렌더 0.107초 → 0.100초. 앞은 고치기 전(사람 마스크를 사진 크기로 늘려 흐림), 뒤는 고친 뒤(분석기 마스크 크기에서 흐림)다.
- 이 Mac에서는 차이가 작다(체형 몫 약 0.05초 → 0.035초). Core Image가 큰 반지름 흐림을 이미 줄여서 계산하기 때문으로 보인다. 메모리와 iPhone·iPad 시간은 재지 않았다.
- 사람 인스턴스는 torso-01·lines-01 1개, couple-body-01 2개였다. 이 기계에서 인스턴스 때문에 건너뛴 검사는 없다.

### 건너뛴 것

- torso-01 허벅지 ±1: 사진이 허벅지 중간에서 잘려 무릎 관절이 없다.
- couple-body-01 남성 개인 층 부유방의 한쪽: 그 높이에서 위팔이 몸통에 붙어 옆선 점이 없다(로그 `body0Side1 skipped`).
- 기존 `RealPhotoAcceptanceTests.testEyeAndLipFeaturesAreVisible`(치아 미백, 데모 사진이 다문 입).

### 부유방이 바뀌지 않는 경우

- 부유방은 겨드랑이 아래 위팔이 가슴 옆에 붙은 쪽에서는 아무것도 하지 않는다. 사진 준비 때 사람 마스크에서 몸통 옆선을 찾고, 배경을 만나기 전에 위팔 보호 띠에 닿으면 그쪽 원소를 만들지 않기 때문이다.
- 부유방 이동은 torso-01(손을 허리에 짚어 위팔과 옆가슴 사이로 배경이 보이는 사진)에서 확인했다.
- couple-body-01은 남녀·이웃 규칙을 확인한다. 위팔과 옆가슴 사이 틈은 네 쪽 중 세 쪽에 있고(남자 화면 오른쪽 위팔은 몸통에 붙음), 옆선 점이 있는 쪽만 이동과 팔 영역을 쟀다.
- 대상 몸에 부유방 높이 옆선 점이 한쪽도 없으면 체형 패널이 부유방 슬라이더 아래에 "팔이 몸에 붙어 있으면 부유방은 바뀌지 않아요."를 보인다(Mac 앱 테스트로 판정만 확인, 화면은 보지 않음).

### 스펙과 다르게 한 것

몸통 옆선·턱밑 그늘 약화·사진 재생성은 설계 문서에 적었다. 팔 상수는 설계 문서에 값이 없는 E 상수라 커밋 메시지와 `RenderTuning` 주석에 이유를 적었다.

- 부유방과 몸 전체 가슴 원소는 어깨~엉덩이 관절선 점이 아니라 인물 마스크에서 찾은 몸통 옆선에 둔다. Vision 어깨 관절이 팔이 붙는 자리라 관절선 점이 팔 보호 안에 들어가 이동이 0이 되었기 때문이다.
- 옆선 탐색은 보호 반지름에 가장자리 띠(feather)까지 더해 팔에 붙은 것으로 본다. 찾은 점이 보호가 이동을 줄이는 띠 안에 들지 않게 한다.
- 팔 최대 이동 `bodyArmMaxShift`를 어깨 폭의 2%에서 3%로 올렸다. 손을 허리에 짚은 사진에서 아래팔 안쪽 원소가 배경 위에 있어 배경 보호로 0.9 폰 px만 움직였다.
- 턱밑 그늘 밝히기에 워프와 같은 옆얼굴 약화를 곱한다.
- 수용 사진 torso-01은 한 번, couple-body-01은 두 번 다시 만들었다(생성 호출 모두 8번, 예산 소진). 마지막 커플 사진은 남자 한쪽 위팔이 몸통에 붙어 부유방 이동의 1차 근거를 torso-01로 두었다(컨트롤러 판정).
- 최종 리뷰 수정: 보호 워프의 사람 마스크 흐림을 사진 크기가 아니라 분석기 마스크 크기에서 한다. Vision 마스크(512×384)와 사진의 가로세로 비가 달라 덜 촘촘한 축만 먼저 늘려 두 축 모두 같은 σ가 되게 했다. 수용 실측 값은 고치기 전과 소수 둘째 자리까지 같다.
- 최종 리뷰 수정: 인스턴스 배정을 포기하는 "사람이 인스턴스보다 많음"은 쓸 수 있는 몸 수로만 센다. 몸 없이 작게 찍힌 행인 얼굴 때문에 커플 사진이 이웃 보호를 잃지 않게 한다.
- 최종 리뷰 수정: 성별 그룹 대상인데 그 성별 얼굴과 짝인 몸이 없으면 "이 사람의 몸을 찾지 못했어요"로 슬라이더를 끈다(0이 아닌 값은 되돌릴 수 있음). 그룹 대상에도 "이 사람" 문구를 그대로 쓴다. 얼굴이 없는 사진에서는 "여성 그룹이나 사람을 골라" 안내를 숨긴다(Mac 앱 테스트로 판정만 확인, 화면은 보지 않음).
- 커플 남녀 검사는 컨트롤러 판정대로 "여성 그룹 부유방은 여성 몸이 받고 남성 몸은 0, 남성 인스턴스 안 변화 0.2% 이하, 이동은 옆선 점이 있는 쪽만"이다.

### CI 결과

- 실행 1: `apple-checks.yml` workflow_dispatch, 실행 39554546320, 커밋 `97b6e08`, 성공.
- 실행 2: 같은 워크플로, 실행 39557719946, 커밋 `3dc0e00`(최종 리뷰 수정 포함), 성공, 38분.
- 실행 2의 패키지 테스트는 545개 중 2개 건너뜀, 실패 0이다.
- 건너뛴 두 개는 기존 `testEyeAndLipFeaturesAreVisible`(다문 입)과 `VisionPersonInstanceAnalyzerTests.testDemoPortraitHasOneInstanceOrNone`(이 기계에서 인스턴스 마스크 없음)이다.
- 그런데도 같은 실행의 수용 테스트에서 커플 사진은 인스턴스 2개를 얻었다. 그래서 남녀 규칙과 이웃 보호 검사는 CI에서도 건너뛰지 않고 돌았다(남성 인스턴스 안 변화 0.0000, 여성 옆선 7.99·7.92 폰 px, 남성 개인 층 10.65 폰 px).
- 실행 2의 앱 테스트는 iOS 시뮬레이터 110개, Mac 111개가 모두 통과했고 UI 테스트도 성공했다.
- 그 뒤 커밋 `6a54714`는 계획 문서 한 줄만 고쳐 CI를 다시 돌리지 않았다.

### 미검증 (사용자 확인 필요)

- 실제 커플·상반신 사진에서 이중턱·부유방·허리를 켰을 때 과하거나 어색한지(TestFlight).
- 실제 사진에서 팔을 내린 자세면 부유방이 거의 바뀌지 않는데, 그것이 납득되는지와 안내 문구가 보이는 때가 맞는지.
- 다섯 명 이상 단체 사진에서 전체 층 체형이 옆 사람을 끌지 않는지(인스턴스 마스크는 4명까지라 5명 이상은 배경만 보호한다).
- 수동 편집이 있는 옛 세션(잠긴 사진)에서 배경 보호와 "전체 층 체형은 모든 사람"으로 결과가 조금 바뀌는 것이 문제 없는지.
- 체형 패널 대상 칩·부유방 안내·"이 사람의 몸을 찾지 못했어요"·다리 길게 안내의 화면 배치(iPhone·iPad·Mac).
- iPhone·iPad에서 원본 해상도 저장 시간과 메모리(Mac 측정만 있음).
- iPhone·iPad 실기기에서 위 항목 전부.

이전 절의 미검증 항목은 그대로 승계한다.

## 인물 보정 G5-1 복구 결함·표 인하 (2026-10-21)

- 브랜치 `beauty-g5`, `5e56ba7`(상수 변경 문서)부터 이 절의 커밋까지다.
  시작은 `ef510c2`다.
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- 이 절의 검증은 모두 자동 테스트와 Evoto 하네스 실행이다.
  앱을 띄워 화면을 보거나 조작한 검증은 없다.
- iOS 시뮬레이터 테스트·실기기는 하지 않았다(로컬 시뮬레이터 금지 규칙).
  배포·푸시·태그는 하지 않았다.

### 자동 검증

- `cd apple && swift test` 종료 코드 **0**.
  패키지 **462**(MellowShared 69, MellowRendering 300(2 건너뜀), MellowLibrary 34, MellowExport 4, MellowEditing 55).
- 시작 전 실측은 패키지 456(Rendering 294), Mac 앱 101이다.
  G5-1이 더한 테스트는 Rendering 6(복구 2, 오검출 거절 2, 몸 피부 밝기 1, 데모 원반 잔차 1)이다.
- Mac 앱 테스트(`xcodebuild … -destination 'platform=macOS' test`) 종료 코드 **0**, **101**개 통과.
- `swift format lint --strict` 출력 없음.
  `./scripts/verify-modules.sh` 통과.
- iOS 시뮬레이터용 빌드만 성공했다(`generic/platform=iOS Simulator`, 부팅 없음).
- `./scripts/test-apple.sh` 전체 실행과 CI(Xcode 26.3)는 하지 않았다.

### 복구 결함 실측

| 항목 | 경계 | 옛 복제 | G5-1 |
|---|---|---|---|
| 합성 경사 위 수동 잡티, 원 안 Y − 고리 Y(/255) | ≤ 1 | 9.24 | 0.81 이하(스크래치패드 9개 위치 탐색의 최대, 저장소 테스트는 한 위치) |
| 데모 볼 아래 경사면에 심은 어두운 원, 복구 원 안 Y − 고리 Y(/255) | ≤ 3 | 18.14 | 1.09 |
| 같은 원의 복구 전 잔차(심은 결함이 보이는지) | > 3 | 9.56 | 9.56 |

- "옛 복제" 값은 배율 상한을 1로 두어(배율 1 = 옛 복제와 같은 식) 같은 테스트를 돌린 값이다.
- 옛 복제는 심은 원(9.6)보다 더 큰 원반(18.1)을 만들었다.
  1.4.0 원반 결함이 데모 사진에서도 재현됐다.

### 잡티 오검출 거절 실측

| 사진 | 옛 규칙 검출 수 | G5-1 검출 수 |
|---|---|---|
| 데모 사진 | 3 | 0 |
| 커플 사진(두 얼굴) | 11 | 4 |

- 데모 사진에서는 자동 잡티가 아무것도 고르지 않게 됐다.
  원터치가 데모 사진에서 잡티를 고치는 효과는 이제 없다(G5-2 점 지우기가 대신한다).
- 데모의 옛 검출 3개는 모두 오검출이었다(검토에서 검출기 계측과 잘라 보기로 확인).
  (487,798)은 바깥 눈꼬리·쌍꺼풀 주름이고 중심 마스크 0.61이다.
  (551,749)는 눈 밑 주름 선이고 종횡비 4.5·마스크 0.60이다.
  (773,704)는 반대쪽 눈 밑 주름이고 종횡비 3.56·마스크 0.61이다.
- 커플 사진에서 거절된 7개는 눈꼬리·눈썹·머리선(마스크 0.58~0.85)이거나 길쭉했다(종횡비 2.1~3.25).
  남은 4개는 마스크 0.92~1.0이다.

### 원터치 실측 (데모 사진, 실제 Vision, 폰 화면 배율 가로 1170px)

하한(얼굴만, 몸 피부 없음):

| 항목 | 옛 문턱 | 적용 문턱 | 측정값 |
|---|---|---|---|
| 여성 0.6 | ≥ 0.05 | ≥ 0.05(유지) | 0.0673 |
| 남성 0.6 | ≥ 0.05 | **≥ 0.03(내림)** | 0.0469 |
| 공통 0.6 | ≥ 0.05 | ≥ 0.05(유지) | 0.0566 |
| 여성 1 | ≥ 0.10 | ≥ 0.10(유지) | 0.1359 |
| 남성 1 | ≥ 0.06 | ≥ 0.06(유지) | 0.0854 |
| 여성 1 대 남성 1 차이 | ≥ 0.02 | ≥ 0.02(유지) | 0.0378 |
| 커플 남·여·미지정 | ≥ 0.03 | ≥ 0.03(유지) | 0.0699 · 0.2078 · 0.0947 · 0.1666 |

- 내린 문턱은 남성 0.6 하나다.
  표 인하 뒤 측정값 0.047이 옛 문턱 0.05에 못 미쳤고 스펙 G5 1.2의 새 문턱(0.03)으로 내렸다.
  여유는 0.017이다.
- 공통 0.6의 옛 문턱 여유는 0.0066뿐이다.

상한·밝기 하한(몸 피부 포함 전체 대상 결과):

| 경우 | 피부 ΔY(0.6: 0.5~3.0, 1: ≤ 4.0) | 중간 대역 비(0.6 ≥ 0.80, 1 ≥ 0.70) | 넓은 대역 비(0.6 ≥ 0.85, 1 ≥ 0.80) | Cr 표준편차 비(0.6 ≥ 0.80, 1 ≥ 0.70) | 다크서클 띠 ΔY(1 ≤ 10.5) | 팔자 띠 ΔY(1 ≤ 6.7) | fine 비 | p99 \|ΔY\| |
|---|---|---|---|---|---|---|---|---|
| 여성 0.6 | 1.06 | 0.855 | 0.874 | 0.931 | — | — | 0.969 | 9.9 |
| 남성 0.6 | 0.80 | 0.892 | 0.892 | 0.941 | — | — | 0.970 | 7.3 |
| 공통 0.6 | 0.90 | 0.875 | 0.883 | 0.935 | — | — | 0.970 | 8.9 |
| 여성 1 | 1.83 | 0.775 | 0.804 | 0.889 | 6.53 | 4.66 | 0.953 | 15.8 |
| 남성 1 | 1.38 | 0.835 | 0.832 | 0.907 | 5.67 | 3.50 | 0.958 | 12.0 |
| 공통 1 | 1.55 | 0.807 | 0.818 | 0.897 | 6.17 | 3.91 | 0.956 | 14.1 |

- 피부·입술 색차, 눈썹, 얼굴 밖 상한은 모두 G4 문턱 안이다(눈썹 0.001, 얼굴 밖 0).
- 몸 피부(얼굴 다각형 밖) 평균 ΔY: 0.6에서 0.87(≤ 1.5), 1에서 1.55(≤ 2.5).
- 여성 1의 넓은 대역 비 여유는 0.004뿐이다.

### Evoto 하네스 중간 실측 (G5-1 표, 자동 잡티 켜짐, 점 지우기 없음)

G5-3 몫의 최종 측정이 아니다. 원반이 사라졌는지 나란히 보기 PNG로 보려고 한 번 돌렸다. 피부 보정 계열 7쌍 중앙값이다.

| 차원 | 1.4.0 0.6(스펙 표) | G5-1 0.6 | G5-1 1.0 | Evoto | 하네스 경계(0.6 / 1) |
|---|---|---|---|---|---|
| 얼굴 피부 ΔY | +2.4 | +1.01 | +1.75 | +1.89 | +0.5~+3.0 / ≤ +4.0 |
| 몸 피부 ΔY | +1.7 | +0.87 | +1.52 | +0.29 | ≤ +1.5 / ≤ +2.5 |
| 중간 대역 비 | 0.66 | 0.827 | 0.734 | 0.994 | ≥ 0.80 / ≥ 0.70 |
| 넓은 대역 비 | 0.79 | 0.911 | 0.858 | 1.075 | ≥ 0.85 / ≥ 0.80 |
| 질감 비 | 0.74 | 0.862 | 0.795 | 0.666 | ≥ 0.65 / ≥ 0.55 |
| 어두운 점 비 | 0.97 | 0.959 | 0.947 | 0.591 | G5-2 몫 |
| 밝은 점 비 | 0.99 | 0.990 | 0.977 | 0.629 | G5-2 몫 |
| Cr 표준편차 비 | — | 0.888 | 0.822 | 0.901 | ≥ 0.80 / ≥ 0.70 |
| 다크서클 띠 ΔY(전용 2쌍) | +11.0 | +7.19 | **+11.10** | +8.01 | +5~+9 / ≤ +10.5 |
| 팔자 띠 ΔY(전용 2쌍) | +7.0 | +4.40 | **+7.20** | +5.13 | +3~+6 / ≤ +6.7 |

- 강도 1의 다크서클·팔자 띠가 하네스 상한을 넘는다(+11.1 > +10.5, +7.2 > +6.7).
  데모 사진 수용 테스트(6.5·4.7)는 넘지 않아 이 계획에서는 표를 더 내리지 않았다.
  G5-3 하네스 실행에서 다시 재고 넘으면 표를 내린다(스펙 위험 항목).
- 나란히 보기(`g5/g5-1/blemish-removal_blemishRemover_section01_01_app.zoom.png`, `ai-skin-retouching_section01_01_app.zoom.png`)에서 1.4.0의 복제 원반(이마·눈 밑·볼·코 옆 4개, 손등·턱 2개)이 보이지 않는다.
  주근깨는 그대로 남는다(G5-2 몫).

### 바뀐 상수·표 값

- 표: 매끄럽게 0.16/0.20/0.12, 얼룩 고르기 0.08/0.10/0.05, 다크서클 0.42/0.45/0.38, 팔자 0.32/0.36/0.28, 몸 피부 밝기 0.08.
  수용 실측 뒤 더 바꾼 표 값은 없다.
- `RenderTuning` 추가: `healLowBandScale` 0.3, `healRingInnerScale` 1.0, `healRingRadiusScale` 0.5, `healMaxGain` 2.0, `healLumaFloor` 0.01, `blemishCenterMaskMinimum` 0.9, `blemishMaxAspect` 2.0, `blemishMinFill` 0.4.

### 스펙과 다르게 한 것

- (G5-1 구현 중 변경, 스펙 5.1에 먼저 적음) `healLowBandScale` 0.6 → 0.3, `healRingRadiusScale` 1.5 → 0.5.
  스펙 값은 합성 경사 잔차 3.6/255로 문턱 1/255를 넘었다.
  원본 패치의 얼룩이 그대로 옮겨지고 넓은 고리 흐림이 먼 피부까지 평균에 넣었기 때문이다.
- 오검출 가장자리 테스트는 합성 얼굴의 가장 아래(턱 끝) 윤곽점을 쓴다.
  합성 얼굴은 윤곽이 피부 타원보다 넓어 가장 왼쪽 윤곽점은 배경이다.
- 데모 원반 잔차는 복구 원(잡티 반지름 × 1.8) 기준으로 잰다.
  원 안은 복구 반지름의 0.65배, 고리는 1~1.5배다.
  계획의 "잡티 반지름 기준"은 고리가 복구 원 안에 들어가 원반과 둘레를 비교하지 못한다.
- 배율 상한 테스트는 검은 원본 대신 감마 0.2 회색 원본으로 잰다.
  검은 원본은 옛 복제에서도 통과해 상한을 검증하지 못한다.

### 미검증 (사용자 확인 필요)

- 실기기에서 수동·자동 잡티 복구에 원반이 없는지, 표를 내린 원터치가 "덜 뿌옇고" 여전히 보이는지.
- 남성 0.6 보임 하한을 0.05 → 0.03으로 내린 판정(스펙의 사전 승인 범위 안).
- 하네스의 강도 1 다크서클·팔자 상한 초과(G5-3에서 결정).
- CI(Xcode 26.3)의 패키지·Mac·iOS 시뮬레이터 앱 테스트와 UI 테스트.

## 인물 보정 G5-2 점 지우기 (2026-10-21)

- 브랜치 `beauty-g5`, `4bdb01c`부터 이 절의 커밋까지다.
- 이 절은 G5-2의 중간 기록이다.
  최종 표와 문서는 G5-3이 쓴다(스펙 8절).
- 앱을 띄운 검증, iOS 시뮬레이터 테스트, 실기기, CI(Xcode 26.3)는 하지 않았다.
  배포·푸시·태그는 하지 않았다.

### 자동 검증

- `cd apple && swift test` 종료 코드 **0**.
  패키지 473(MellowShared 70, MellowRendering 310(2 건너뜀), MellowLibrary 34, MellowExport 4, MellowEditing 55).
- Mac 앱 테스트 **101**개 통과.
- `swift format lint --strict` 출력 없음.
  `./scripts/verify-modules.sh` 통과.
- iOS 시뮬레이터용 빌드만 성공했다(부팅 없음).

### Evoto 하네스 (피부 보정 계열 7쌍 중앙값, 점 지우기 어두운 점만)

| 차원 | G5-2 0.6 | G5-2 1.0 | 남성 0.6 | 1.4.0 표 0.6 | Evoto | 경계(0.6 / 1) | 남성 0.6 경계 |
|---|---|---|---|---|---|---|---|
| 어두운 점 비 | **0.829** | 0.801 | **0.865** | 0.956 | 0.591 | 합격선 ≤ 0.76(목표 0.70) / ≥ 0.47 | ≤ 0.80, 보임 하한 ≤ 0.85 |
| 밝은 점 비 | 0.920 | 0.911 | 0.940 | 0.991 | 0.629 | ≤ 0.80 / ≥ 0.52 | — |
| 중간 대역 비 | **0.774** | 0.683 | **0.809** | 0.662 | 0.994 | ≥ 0.80 / ≥ 0.70 | ≥ 0.85 |
| 넓은 대역 비 | 0.902 | 0.844 | 0.919 | 0.806 | 1.075 | ≥ 0.85 / ≥ 0.80 | — |
| 질감 비 | 0.765 | 0.723 | 0.799 | 0.741 | 0.666 | ≥ 0.65 / ≥ 0.55 | ≥ 0.70 |
| 모공 크기 점 비 | 1.000 | 1.000 | 1.000 | 1.000 | 0.622 | ≥ 0.90 / ≥ 0.85 | — |
| 얼굴 피부 ΔY | +1.85 | +2.60 | +1.53 | +2.13 | +1.89 | +0.5~+3.0 / ≤ +4.0 | 같음 |
| 다크서클 띠 ΔY(2쌍) | +8.13 | **+12.04** | +7.29 | +10.35 | +8.01 | +5~+9 / ≤ +10.5 | 같음 |
| 팔자 띠 ΔY(2쌍) | +5.97 | **+8.75** | +5.09 | +6.97 | +5.12 | +3~+6 / ≤ +6.7 | 같음 |

- 굵게 쓴 값은 경계를 넘지 못한 것이다.
- 어두운 점 비 합격선(0.6에서 ≤ 0.76, 목표 0.70)은 넘지 못했다(0.829).
- 남성 0.6은 어두운 점 비 0.865로 보임 하한(≤ 0.85)과 남성 경계(≤ 0.80)를 넘지 못했고, 중간 대역 비 0.809로 남성 하한(≥ 0.85)에 못 미친다.
  남성 점 지우기 표를 0.75 → 0.4로 내린 대가다(데모 남녀 차이를 만들려고 내렸다).
- 어두운 점 비를 재는 1.2% 닫힘에는 모공 크기 명암도 들어간다.
  우리는 모공을 남기고(모공 비 1.00) Evoto는 지운다(0.62).
- 중간 대역 비는 0.6에서 0.774로 하한 0.80 아래다.
  점을 지우지 않은 G5-1 표는 0.827이었다.
- 강도 1의 다크서클·팔자 띠는 상한을 넘는다.
  G5-3이 표를 내렸다(아래 G5 최종 절).
- 나란히 보기(`g5/g5-2-fix1/*.zoom.png`)에서 주근깨는 옅어졌지만 남는다.
  콧구멍·눈꼬리는 그대로이고, 얼굴 밖 번짐과 원반은 없다.

### 남은 간극 (사용자 확인 필요)

- **밝은 점(땀 반사점·좁쌀)은 지우지 않는다.**
  밝은 점 빼기는 `spotBrightAmount` 0으로 꺼 두었다.
  켜면 데모 원터치 0.6의 피부 밝기가 +0.2~0.6/255로 하한 +0.5 아래가 되고, 중간 대역 비가 0.75~0.79로 하한 0.80 아래가 됐다.
  하네스 밝은 점 비는 0.920이다(Evoto 0.629).
- 데모에 심은 밝은 점 3개의 회복률은 −0.04·0.06·0.48로 기록만 한다.
- **어두운 점 비 0.829는 합격선 0.76을 넘지 못했고 코디네이터 판정으로 받아들였다.**
  1.2% 닫힘이 모공 크기 명암도 세는데 우리는 모공을 남긴다(모공 비 1.00, Evoto 0.62).
- **공통 0.6 하네스 중간 대역 비 0.774는 하한 0.80 아래이고 코디네이터 판정으로 받아들였다.**
  데모 수용 테스트(0.861)는 하한을 넘는다.
- **남성 0.6 하네스 어두운 점 비 0.865(보임 하한 ≤ 0.85)·중간 대역 비 0.809(≥ 0.85) 미달을 코디네이터 판정으로 받아들였다.**
  남성 점 지우기 표는 0.75에서 0.4로 내렸다.
  데모 원터치 0.6 어두운 점 회복률은 남성 0.713, 여성 0.863이다.
  G5-3에서 0.5를 시험했지만 데모 남성 0.870이 여성 0.865보다 높아 남녀 차이가 사라져 0.4를 유지했다.
- 렌더 시간(데모 미리보기 1254², 원터치 0.6, 데워진 컨텍스트, 3회 평균)은 점 지우기를 켜면 8.0ms, 끄면 7.4ms다.
  처음 렌더(커널 컴파일 포함) 시간은 재지 않았다.

## 인물 보정 G5 Evoto 보정 재조정 (2026-10-22)

- 브랜치 `beauty-g5`, G5-1 `5e56ba7`부터 G5-3 마지막 커밋까지다(G5-3은 `75dae07`부터).
  위 G5-1·G5-2 절은 중간 기록이고 이 절이 최종이다.
- 환경: macOS 26.6.2, Xcode 27.1, Mac17,9. CI는 Xcode 26.3이다.
- 모두 자동 테스트와 Evoto 하네스 실행이다.
  화면 조작, iOS 시뮬레이터 테스트, 실기기 검증, 배포·푸시·태그는 하지 않았다.

### 자동 검증 (G5-3 마지막 코드)

- `./scripts/test-apple.sh` 종료 코드 **0**(로컬이라 iOS 시뮬레이터 앱 테스트는 생략).
  모듈 경계 검사, `swift format lint --strict`, xcodegen 동기화, 패키지 테스트, Mac 앱 테스트가 들어 있다.
- 패키지 **478**(MellowShared 71, MellowRendering 314(2 건너뜀), MellowLibrary 34, MellowExport 4, MellowEditing 55).
  G5-2 끝(473) 대비 G5-3이 더한 것: Shared 1(원터치 얼룩 색 고르기 표), Rendering 4(얼룩 색 고르기 단위 2, 데모 보라 얼룩 수용 1, 밝은 점 형태 필터 생략 바이트 동일 1).
- Mac 앱 테스트 **101**개 통과.
- iOS 시뮬레이터용 빌드(`generic/platform=iOS Simulator`, 부팅 없음): **BUILD SUCCEEDED**.
- CI(Xcode 26.3): 컨트롤러가 CI로 확인.

### Evoto 하네스 실측

G5-3 하네스는 다크서클·팔자 전용 쌍(각 2쌍)만 최종 코드로 쟀다.
피부 보정 계열 7쌍 전체 실행은 하지 못했다.
Evoto 이미지와 이전 출력이 있던 스크래치패드가 세션 중에 지워졌기 때문이다(이미지는 저장소 밖 로컬 전용).
그래서 아래 피부 보정 계열 값은 G5-2 코드(얼룩 색 고르기 없음)의 실측이고, 얼룩 색 고르기가 바꾸는 Cr 표준편차 비·붉은 얼룩 비는 하네스로 재지 못했다.

다크서클·팔자 띠(전용 2쌍씩 중앙값, G5-3 최종 코드):

| 차원 | 공통 0.6 | 공통 1.0 | 여성 0.6 | 여성 1.0 | 남성 0.6 | 남성 1.0 | 1.4.0 표 1.0 | Evoto | 경계(0.6 / 1) | 판정 |
|---|---|---|---|---|---|---|---|---|---|---|
| 다크서클 띠 ΔY | +6.70 | +10.04 | +6.80 | +10.20 | +6.05 | +9.37 | +10.35 | +8.01 | +5~+9 / ≤ +10.5 | 합격 |
| 팔자 띠 ΔY | +4.37 | +6.23 | +4.39 | +6.26 | +3.95 | +6.05 | +6.97 | +5.12 | +3~+6 / ≤ +6.7 | 합격 |

- 같은 실행에서 바꾸기 전 표(다크서클 0.42, 팔자 0.32)는 공통 1.0에서 +12.05·+8.76이었다.
- 1.4.0 표 열은 G5-2 실측(legacy 계열)이다.

피부 보정 계열(7쌍 중앙값, G5-2 코드):

| 차원 | 우리 0.6 | 우리 1.0 | 남성 0.6 | 1.4.0 표 0.6 | Evoto | 경계(0.6 / 1) | 판정 |
|---|---|---|---|---|---|---|---|
| 어두운 점 비 | 0.829 | 0.801 | 0.865 | 0.956 | 0.591 | 합격선 ≤ 0.76(목표 0.70) / ≥ 0.47 | **미달**(0.6), 남성 보임 하한 ≤ 0.85 **미달** |
| 밝은 점 비 | 0.920 | 0.911 | 0.940 | 0.991 | 0.629 | ≤ 0.80 / ≥ 0.52 | **미달**(밝은 점 빼기 꺼짐) |
| 중간 대역 비 | 0.774 | 0.683 | 0.809 | 0.662 | 0.994 | ≥ 0.80 / ≥ 0.70, 남성 ≥ 0.85 | **미달**(0.6·1.0·남성) |
| 넓은 대역 비 | 0.902 | 0.844 | 0.919 | 0.806 | 1.075 | ≥ 0.85 / ≥ 0.80 | 합격 |
| 질감 비 | 0.765 | 0.723 | 0.799 | 0.741 | 0.666 | ≥ 0.65 / ≥ 0.55, 남성 ≥ 0.70 | 합격 |
| 모공 크기 점 비 | 1.000 | 1.000 | 1.000 | 1.000 | 0.622 | ≥ 0.90 / ≥ 0.85 | 합격 |
| 얼굴 피부 ΔY | +1.85 | +2.60 | +1.53 | +2.13 | +1.89 | +0.5~+3.0 / ≤ +4.0 | 합격 |

- 중간 대역 비 1.0은 0.683으로 하한 0.70 아래다(G5-2 절 표와 같은 값).
- 나란히 보기 PNG로 볼의 보라 얼룩이 줄었는지, 색이 뜨지 않았는지는 보지 못했다(하네스 출력 없음).

### 원터치 실측 (데모 사진, 실제 Vision, 폰 화면 배율, G5-3 최종 코드)

하한(얼굴만, `changedFraction`): 여성 0.6 0.147, 남성 0.6 0.096, 공통 0.6 0.135, 여성 1 0.236, 남성 1 0.160, 여성 1 대 남성 1 차이 0.039, 커플 남 0.275·여 0.334·미지정 0.337·0.296.
모두 옛 문턱(0.05·0.05·0.05·0.10·0.06·0.02·0.03)을 넘는다.
남성 0.6 문턱만 G5-1에서 0.03으로 내려 둔 그대로다.

상한·밝기 하한(몸 피부 포함 전체 대상):

| 경우 | 피부 ΔY | 중간 대역 비 | 넓은 대역 비 | Cr 표준편차 비 | 다크서클 띠 | 팔자 띠 | fine 비 | p99 \|ΔY\| |
|---|---|---|---|---|---|---|---|---|
| 여성 0.6 | 2.52 | 0.841 | 0.900 | 0.840 | — | — | 0.931 | 11.3 |
| 남성 0.6 | 1.91 | 0.878 | 0.908 | 0.877 | — | — | 0.937 | 8.4 |
| 공통 0.6 | 2.38 | 0.861 | 0.908 | 0.848 | — | — | 0.932 | 10.4 |
| 여성 1 | 3.33 | 0.766 | 0.836 | 0.756 | 6.61 | 4.63 | 0.916 | 15.9 |
| 남성 1 | 2.81 | 0.824 | 0.855 | 0.808 | 6.10 | 4.06 | 0.923 | 12.6 |
| 공통 1 | 3.11 | 0.798 | 0.848 | 0.766 | 6.53 | 4.29 | 0.920 | 14.6 |
| 경계 | 0.6: 0.5~3.0, 1: ≤ 4.0 | ≥ 0.80 / ≥ 0.70 | ≥ 0.85 / ≥ 0.80 | ≥ 0.80 / ≥ 0.70 | ≤ 10.5 | ≤ 6.7 | ≥ 0.9 / ≥ 0.85 | ≤ 60 |

- 몸 피부 평균 ΔY: 0.6에서 0.97(≤ 1.5), 1에서 1.67(≤ 2.5).
- 눈썹 changedFraction 최대 0.0018, 얼굴 밖 0.

심은 결함(데모 사진):

| 항목 | 경계 | 실측 |
|---|---|---|
| 점 지우기 1, 어두운 점 6개 평균 회복률 | ≥ 0.7 | 0.842 |
| 점 지우기 1, 밝은 점 3개 평균(기록만) | — | 0.166 |
| 점 지우기 1, 원 밖 fine 비 · 모공 비 | ≥ 0.9 · ≥ 0.9 | 0.960 · 1.043 |
| 점 지우기 1, 제외 원 평균 \|ΔY\| | ≤ 1.0 | 0.22 |
| 점 지우기 1, 콧구멍 띠 99분위 \|ΔY\|(G5-3 신설) | ≤ 8 | 6.70(제외를 끄면 9.40으로 실패하는 것을 확인) |
| 점 지우기 1, 얼굴 마스크 영역 밖 최대 바이트 | ≤ 1 | 0 |
| 원터치 0.6 어두운 점 회복률 여성 · 공통 · 남성 | ≥ 0.6 · ≥ 0.6 · ≥ 0.4 그리고 여성 − 0.05 이하 | 0.865 · 0.863 · 0.712 |
| 자동 잡티 원반 잔차(복구 뒤 · 심은 원) | ≤ 3 · > 3 | 1.09 · 9.56 |
| 얼룩 색 고르기 1, 보라 얼룩 Cb · Cr 제거율 | ≥ 0.5 | 0.576 · 0.572 |
| 얼룩 색 고르기 1, 원 안 \|ΔY\| · fine 비 · 중간 대역 휘도 비 | ≤ 1.5 · ≥ 0.9 · ≥ 0.95 | 0.206 · 0.997 · 0.997 |

- 보라 얼룩 원 안 휘도 변화는 2026-10-22 G5·I 통합 트리에서 평균 |ΔY|로 다시 재어 0.2057/255였다.
  이전 0.05는 |평균 ΔY|라 밝아진 픽셀과 어두워진 픽셀이 상쇄된 값이었다.
  판정 상한 1.5/255와 제품 코드는 바꾸지 않았다.

- 렌더 시간(데모 미리보기, 원터치 0.6, 데워진 컨텍스트, 3회 평균): 점 지우기 켬 7.1ms, 끔 6.1ms.
  밝은 점 형태 필터 4번을 건너뛴 뒤의 값이다(G5-2는 8.0·7.4ms, 같은 Mac이지만 다른 실행).

### 바뀐 상수·표 값 (1.4.0 → G5)

- 표(공통/여성/남성): 매끄럽게 0.35/0.45/0.25 → 0.16/0.20/0.12, 얼룩 고르기 0.25/0.35/0.15 → 0.08/0.10/0.05, 다크서클 0.55/0.6/0.5 → 0.30/0.30/0.28, 팔자 0.4/0.45/0.35 → 0.12/0.08/0.14, 몸 피부 밝기 0.15 → 0.08.
- 새 항목: 점 지우기 1.0/1.0/0.4, 얼룩 색 고르기 0.5/0.5/0.35, 자동 잡티 true → false 덮어쓰기.
- G5-3 `RenderTuning` 추가: `chromaBlotchFraction` 0.025, `chromaEveningMax` 1.0.
  G5-1·G5-2 상수는 위 두 절에 있다.
- 얼룩 색 고르기 표 값은 시작값 그대로다.
  데모 원터치 Cr 표준편차 비가 0.6에서 0.840~0.877(≥ 0.80)이라 0.3 → 0 내림 규칙이 걸리지 않았다.
- 내린 보임 문턱은 G5-1의 남성 0.6(0.05 → 0.03) 하나다.

### 스펙과 다르게 한 것 (G5-3, 모두 스펙에 먼저 적음)

- 얼룩 색 고르기 흐림 반지름 0.06 → 0.025와 하한 mid → fine.
  6%는 반지름 6% 얼룩 색의 약 40%만 담아 제거율이 데모 0.18이었다.
- 얼룩 색 고르기를 선형 값이 아니라 화면 값(sRGB 감마)에서 재고 뺀다.
  선형에서 빼면 화면 Y가 1~1.3/255 바뀌었다(합성 단위 테스트 경계 1/255).
- 심은 보라 얼룩 제거율은 깨끗한 사진을 같은 레시피로 렌더한 결과와 비교한다(점 지우기 회복률과 같은 방식).
- 다크서클 0.42/0.45/0.38 → 0.30/0.30/0.28, 팔자 0.32/0.36/0.28 → 0.12/0.08/0.14.
  점 지우기·매끄럽게가 띠를 함께 밝혀 주름 값이 0이어도 팔자 띠가 약 4.7 남는다.
  여성은 다른 항목이 띠를 더 밝혀 팔자 표 값이 남성보다 낮다.
- 점 지우기 제외 영역 단언에 콧구멍 띠 99분위 \|ΔY\| ≤ 8을 더했다(평균은 제외를 꺼도 0.32라 판별하지 못했다, G5-2 리뷰).
- 밝은 점 빼기가 꺼져 있으면 밝은 점 형태 필터 4번을 건너뛴다(같은 바이트, G5-2 리뷰).

### 남은 간극 (사용자 확인 필요)

- **하네스 어두운 점 비 0.829(합격선 ≤ 0.76, 목표 0.70) 미달**, 코디네이터 판정으로 수용.
  우리는 모공 크기 점을 남기고 Evoto는 지운다(모공 비 1.00 대 0.62).
- **하네스 공통 0.6 중간 대역 비 0.774(≥ 0.80) 미달**, 코디네이터 판정으로 수용.
  데모 수용 테스트는 0.841~0.878로 넘는다.
- **하네스 남성 0.6 어두운 점 비 0.865(보임 하한 ≤ 0.85)·중간 대역 비 0.809(≥ 0.85) 미달**, 코디네이터 판정으로 수용.
  남성 점 지우기 0.5 시험은 데모 남녀 차이가 사라져(0.870 대 0.865) 0.4를 유지했고, 하네스로는 재지 못했다.
- **밝은 점(땀 반사점·좁쌀)은 지우지 않는다**(하네스 밝은 점 비 0.920, Evoto 0.629).
- **모공 크기 점**은 일부러 남긴다.
  얼굴 폭 333px 아래 작은 얼굴은 모공 대역이 없어 점 지우기가 모공까지 채운다(형태 필터 반지름 내림, 데모만 단언).
- **ML 없이는 못 하는 것**: 남성 수염 그늘, 눈 밑 지방, 재조명·입체 조각, 잔머리 정리.
- **G5-3 최종 코드의 피부 보정 계열 하네스 미실행**: 얼룩 색 고르기가 Evoto 쌍의 Cr 표준편차 비·붉은 얼룩 비·나란히 보기에서 어떻게 보이는지 재지 못했다.
  이미지를 다시 두면 `MELLOW_EVOTO_DIR=<evimg> MELLOW_EVOTO_OUT=<out> MELLOW_EVOTO_CANDIDATES=1 swift test --filter EvotoCalibrationTests`로 잰다.
- 팔자 표 값이 여성 0.08 < 남성 0.14로 뒤집혔다(띠 상한을 성별마다 지키려고).
- 하네스 표본이 작다(피부 보정 7쌍, 다크서클·팔자 각 2쌍).

### 기기에서 확인할 것

- 주근깨·여드름 자국이 있는 사진에 원터치 → 점이 지워지고 원반이 없는지.
- 볼에 보라·붉은 얼룩이 있는 사진에 원터치 → 얼룩 색이 옅어지고 얼굴색이 뜨지 않는지.
- 남성 사진에서 절제됐으되 보정이 보이는지.
- 원터치 강도 1에서 눈 밑·팔자가 하얗게 뜨지 않는지.
- 세부 조정의 "점 지우기"·"얼룩 색 고르기" 슬라이더와 수동 잡티 복구에 원반이 없는지.


## G5·I 통합 로컬 검증 (2026-10-22)

- 격리 브랜치 `codex/g5-integration`에서 main `8157172`와 beauty-g5 `7f8314b`를 병합했다.
- 병합 커밋은 `c7ad149`이고 독립 리뷰의 검증 결함 수정은 `dc305c5`다.
- 검증한 코드와 릴리스 노트는 `8c4d524` 작업 트리이며 이 절 이후에는 검증 문서만 바뀐다.
- 충돌 5개는 기존 이중턱·부유방·체형 층과 G5 피부 키를 함께 유지하도록 해소했다.
- 환경은 macOS 26.6.2와 Xcode 27.1(27A9275)이다.
- 모든 Swift 명령은 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`로 실행했다.

### 자동 검증

- `CI`와 `MELLOW_IOS_TESTS`를 해제한 `./scripts/test-apple.sh` 종료 코드 **0**.
- 모듈 의존성 검사와 Swift 형식 검사 및 XcodeGen 프로젝트 일치 검사 통과.
- 패키지 **569개**, 실패 **0개**, 건너뜀 **2개**.
  Shared 82개와 Rendering 387개 및 Library 34개와 Export 4개 및 Editing 62개다.
- 건너뜀은 Evoto 입력 이미지 부재와 다문 입 데모 사진의 치아 미백 측정이다.
- Mac 앱 **111개**, 실패 **0개**, `TEST SUCCEEDED`.
- iOS 시뮬레이터 앱 테스트 생략 문구를 확인했고 iOS 테스트는 실행하지 않았다.
- 전체 로그는 `/tmp/mellow-g5-integration-apple.log`다.
- G5 수정 범위의 좁은 패키지 검사 **37개**, 실패 **0개**, 종료 코드 **0**.
- 좁은 검사 로그는 `/tmp/mellow-g5-integration-focused.log`다.
- `/usr/bin/ruby fastlane/test/release_notes_test.rb`는 **6개**와 **18 assertions**, 실패 **0개**, 오류 **0개**, 건너뜀 **0개**로 종료 코드 **0**.

### 독립 리뷰 수정과 릴리스 준비

- `chromaEvening = 0`은 G5-2 `ee1aa28`에서 고정한 이전 커널과 얼룩·번들거림·피부 보정 조합 세 가지에서 같은 바이트임을 확인했다.
- 합성·실사진의 휘도 변화 단언은 |평균 ΔY|에서 평균 |ΔY|로 바로잡았다.
- 실사진 평균 |ΔY|는 **0.2057/255**이며 상한 **1.5/255** 이내다.
- G5-3 계획의 흐림 반지름과 색 공간 설명을 최종 **2.5%**와 **sRGB 감마**로 맞췄다.
- G5와 I의 `fastlane/release_notes/1.4.1.json`을 작성하고 I 전용 `1.5.0.json`은 통합 제거했다.
- 버전 변경과 태그 및 배포는 하지 않았다.
- 이 작업에서 main 변경과 push 및 CI 실행과 J 구현은 하지 않았다.

### 남은 확인

- 이 절은 구현 담당자의 실행 기록이며 독립 검수 완료 판정을 뜻하지 않는다.
- 통합 코드의 CI와 iOS 및 실기기 검증은 이 실행에 포함되지 않는다.
- Evoto 원본 입력이 없어 최종 코드의 외부 사진 쌍 하네스는 다시 실행하지 못했다.
- 위 G5와 I 절의 실사진·기기 확인 항목과 알려진 간극을 그대로 승계한다.


## G5·I 통합 CI 검증 (2026-10-22)

- GitHub Actions `Apple checks` 실행 [39701215480](https://github.com/MJ-0701/mellow-photo/actions/runs/39701215480)은 **success**로 끝났다.
- 검증 커밋은 `codex/g5-integration`의 `2f9dd16be6f76acf6c4ecf8e7e5f1ba283067da1`이다.
- 실행 환경은 `macos-15-arm64`와 Xcode **26.3**이다.
- 모듈 의존성과 형식 검사 및 XcodeGen 프로젝트 일치 검사 통과.
- 패키지 **569개**, 실패 **0개**, 건너뜀 **3개**.
- 건너뜀은 Evoto 입력 이미지 부재와 다문 입 데모 사진의 치아 미백 측정 및 이 CI 기계의 Vision 인스턴스 마스크 미지원이다.
- iPhone 시뮬레이터 앱 **110개**, 실패 **0개**, `TEST SUCCEEDED`.
- iPad 시뮬레이터 앱 **110개**, 실패 **0개**, `TEST SUCCEEDED`.
- Mac 앱 **111개**, 실패 **0개**, `TEST SUCCEEDED`.
- iPhone UI **2개**, 실패 **0개**, `TEST SUCCEEDED`.
- iPhone·iPad arm64 서명 없는 Release 앱과 에셋 및 개인정보 보호 매니페스트 검증 통과.
- Mac 서명 없는 Release 앱 빌드 통과.
- 확인한 CI 로그는 `/tmp/mellow-g5-ci.log`다.
- 위 시뮬레이터 검증은 GitHub Actions에서 수행했고 로컬에서는 실행하지 않았다.
- 이후 병합과 1.4.1 준비는 이 CI 커밋의 제품·테스트 코드를 그대로 유지하고 검증 문서와 버전만 바꾼다.
- 실제 배포와 TestFlight 처리 완료는 이 CI 결과가 보장하지 않는다.
- 앞 절의 실기기·실사진 확인과 Evoto 하네스 재실행 항목은 그대로 남는다.

## 빠른 보정 독립 검수 (2026-10-26)

- 기존 사진의 보정 기능과 사진별 자동 처리를 검수했다. 사진 생성 API나 미채택 옷 주름 연구 모델은 이번 제품 변경에 포함되지 않는다.
- 기능 커밋 `6bda31a`에서 모듈 의존성·엄격한 Swift 서식·생성 프로젝트 일치 검사를 통과했다. 로컬 Xcode 27.1에서 패키지 570개 검사 중 실패 0개·건너뜀 2개, Mac 앱 124개 검사 실패 0개다.
- 건너뜀은 기존 Evoto 외부 입력 미설정과 다문 입 데모 사진의 치아 측정 조건이다. 새 빠른 보정 앱 검사 13개는 모두 실행했다.
- 사진마다 다른 밝기와 얼굴 분석, 일부 분석 실패, 완료분을 유지하는 취소, 취소 중 재시작 차단, 사진을 바꿨다 돌아오는 경우와 수동 편집 후 늦은 결과 차단을 확인했다. 자르기·수동 브러시·얼굴형·개인별 기록 보존, 사진별 한 단계 실행 취소·다시 실행 및 저장된 이력 복원도 확인했다.
- 첫 iPhone 화면 검사 2개는 부모 패널의 접근성 식별자가 자식 버튼 식별자를 덮어 실패했다. 실제 접근성 기록으로 원인을 확인하고 부모 식별자 한 줄을 제거한 `dcfc468`에서 동일한 검사 2개가 통과했다. 실패 기록은 별도로 보존했다.
- 일괄 보정 버튼의 글자 대비를 보완한 최종 제품 커밋 `766d9938848ae09a03161c057669fd153ea0df84`에서 같은 iPhone UI 검사 2개를 다시 실행해 모두 통과했다. iPhone 18 Pro / iOS 27.0 시뮬레이터의 DEBUG 합성 사진 3장만 사용했으며, 테스트 조건이나 버튼 조회를 우회하지 않았다.
- 실제 첨부 화면에서 카드 설명의 줄바꿈, 하단 일괄 보정 접근, 밤 색감 적용 후 되돌리기, 처리 중 다른 도구가 비활성일 때 취소 버튼 접근을 확인했다. [기본 화면](docs/validation/quick-retouch/quick-compact-top.png), [일괄 보정과 밤 색감 설명](docs/validation/quick-retouch/quick-compact-night.png), [처리 중 취소](docs/validation/quick-retouch/quick-compact-cancel.png)를 보존했다.
- Mac 직접 화면 검수는 호스트 잠금으로 수행하지 못했으며 잠금을 우회하지 않았다. 이 보조 시각 검수를 Mac 앱 테스트 통과로 대체해 표시하지 않는다. 직접 관찰한 Mac 배치 결과와 실기기 보정 품질은 이번 검수 범위 밖이다.
- 로컬 검증 로그·화면·파일 해시는 `test-output/quick-retouch-release-review/evidence-index.json`에 연결했다. 원본 Mac 결과는 `apple/build/Logs/Test/Test-MellowPhoto-2026.10.26_18-14-10-+0900.xcresult`, 최종 iPhone 결과는 `/tmp/quick-retouch-review-ui-final.xcresult`다. 검수용 실행과 시뮬레이터는 종료됐고 기존 사용자 앱 PID 815는 그대로 유지했다.
- 이 기록 시점에는 원격 iPhone·iPad 전체 검사 및 Release 번들 검사가 진행 중이다. 최종 배포 커밋의 필수 검사, TestFlight 처리 상태와 Mac ZIP 검증이 끝나기 전 배포 완료로 판정하지 않는다. Mac 직접 시각 검수 미수행은 알려진 기능 실패와 구분해 남긴다.

## 인물 적용 대상·부위 선택 검증 (2026-10-28)

- 사용자가 iPhone에서 남성·여성 그룹을 선택한 조건을 재현했다. 성별 미지정 얼굴은 그룹에 속하지 않았지만 기존 화면은 조정을 허용해, 값과 이력만 바뀌고 결과 사진은 그대로였다. 수정 후에는 적용 인원을 표시하고 대상 없는 인물 조정을 거절하며 전체·개인 선택으로 안내한다.
- 빈 그룹 초기화, 실행 취소·다시 실행·재불러오기, 개인 설정 보존, 전역 몸 피부 조정, 드래그 중 대상 변경을 검사했다. 선택만으로 성별이나 보정값을 바꾸지 않는다.
- 부위 선택과 도구 검색, 이중턱·부유방 직접 진입, 정확한 슬라이더로 이동하는 화면을 구현했다. 몸은 기존 렌더의 유효 관절·옆선·사람 연결을 사용하며, 겹치거나 위치를 보장할 수 없으면 목록으로 안내한다.
- 독립 검수에서 회전·자르기·변형 실행 취소 직후 이전 화면에 새 좌표를 적용할 수 있는 문제를 발견했다. 실패하는 회귀를 남기고 화면 갱신 대기·실패·중단 중 부위 선택을 거절하도록 수정했다. 실제 성공한 렌더 후 다시 선택할 수 있는지 검사했다.
- 첫 제품 고정본 `e1bbe3e`의 독립 필수 검사: 모듈 경계·엄격한 코드 형식·생성 프로젝트 일치 통과, 패키지 570개 중 실패 0개·생략 2개, Mac 앱 138개 실패 0개. 생략은 기존 Evoto 외부 입력 부재와 입을 다문 가상 데모의 치아 측정 조건이다.
- 최종 코드 `39b9a06`에서 독립 추가 회귀 16개가 실패·생략 없이 통과했다. 검사 도구를 우회하지 않았고 보정 효과·보호 기준을 낮추지 않았다.
- 사용자 iPhone 15 Pro의 별도 검증 앱에서 기존 생성 데모의 실제 분석·미리보기 경로가 동작함을 확인했다. 이 결과는 실제 촬영 사진의 일반화나 보이는 화면 검수 결과를 대신하지 않는다. 사용자 사진은 외부로 전송하지 않았다.
- 같은 최종 제품 코드의 별도 검증 앱에서 실제 iPhone 화면 검사 5개가 실패·생략 없이 통과했다. 원터치와 원본 비교·되돌리기, 피부·부유방 슬라이더 실제 값 1.00과 보이는 결과 변화, 빈 남녀 그룹 차단과 전체 선택, 얼굴 네 부위 및 확대·이동 후 부위 선택, 강도·직접 진입을 확인했다.
- 독립 검수자가 첨부 147개와 완료 상태 28개를 해시로 연결하고 캔버스 24개를 전체 화면과 픽셀 단위로 대조했다. 부위 선택만으로 편집값·이력·저장이 바뀌지 않았으며 원본 비교 화면은 기준 원본과 같았다.
- 이 화면 검사는 기존 생성 인물·몸 사진 두 장에 한정한다. 실제 촬영 사진이나 사용자 사진의 일반화 판정이 아니며, 기존 얼굴 효과 5%·형태 이동 2픽셀 및 보호 기준을 화면 차이만으로 대신하지 않는다. 실제 기기의 변형·다시 실행과 개인 선택 안내 버튼 직접 누르기는 이 5개 흐름에 포함되지 않는다. 관련 모델 경계는 앞의 독립 회귀에서 별도로 검사했다.
- 첫 화면 검사의 실패 기록을 보존했다. 검사 도구의 스크롤 지나침·슬라이더 끝점·확대 화면 바깥 제스처를 고쳤으며 제품 코드나 수용 기준을 바꾸지 않았다. 마지막 화면 시나리오의 111.210초에는 검사 도구의 제한된 스크롤 복구가 포함되어 있어 제품 반응 시간으로 해석하지 않는다.
- 원격 검사 40605916905에서 iPhone 앱 139개·iPad 앱 139개·Mac 앱 140개는 실패 없이 통과했으나 기존 화면 검사 4개 중 1개가 스크롤 중 버튼을 찾지 못해 실패했다. 해당 실행의 Release 빌드는 수행되지 않았다. 영상·이벤트에서 목표를 지나친 뒤 같은 방향으로 12회 빠르게 스크롤한 원인을 확인했다. 테스트 전용 수정 `34ff353`은 화면 안의 목표 위치에 따라 짧고 느린 드래그와 방향 전환을 사용하며 밤 색감·한 번의 실행 취소·취소의 기존 조건을 유지한다. 제품 앱 소스는 실기기 검수한 코드와 같다. 구현자와 검수자가 같은 화면 검사 2개를 각각 재실행해 모두 통과했다. 최종 원격 검증·배포 완료는 별도로 기록한다.

## 기존 1.5.0 Mac 화면 후속 확인 (2026-10-28)

- Mac 잠금 해제 후 설치된 1.5.0의 저장된 화면을 읽기 전용으로 확인했다. 같은 코드의 별도 합성 사진 세션에서 밤 색감·되돌리기·일괄 처리 취소와 도구 복귀를 확인했다.
- 기존 사용자 세션 파일은 검사 전후 해시가 같았다. 합성 사진에 얼굴이 없어 이 결과를 인물 보정 품질의 근거로 사용하지 않았다.

## 저장된 개인 조정에 가려진 원터치 진단과 코어 검수 (2026-10-28)

- 사용자 원본과 승인된 선택 사진의 현재 설정·최근 실행 취소 한 단계로 보고된 증상을 재현했다. 전체 강도를 올려도 기존 개인 조정이 얼굴 값을 유지하고 몸 피부 밝기만 달라졌다. 과거 설정을 만든 사용자 행동은 추정하지 않는다.
- 전체 설정의 임시 사본은 선택 사진의 제한된 값만 추린 뒤 삭제했다. 원본과 개인 설정·파생 이미지는 로컬 검사에만 사용했으며 Git이나 원격 검사에 포함하지 않았다. 실제 iPhone의 편집값은 바꾸지 않았다.
- 개인 조정 보존과 명시적 교체를 분리하는 코어를 구현했다. 독립 검수에서 처음 선택한 얼굴의 정상 적용이 거절되는 반례를 발견했고, 수정본 `7851048`에서 같은 반례가 통과했다. 독립 도메인·준비 조건 검사 12개와 앱·기존 흐름 검사 18개가 실패 없이 통과했다.
- 실제 저장 상태의 로컬 재현에서 기본 적용은 변경 없이 기존 개인 조정을 보존했다. 명시적 교체는 준비된 개인 항목 13개를 바꿨으며 다른 색·배경·형태 설정을 유지했다. 한 번의 실행 취소, 다시 실행의 동일 미리보기, 저장 복원과 같은 값 반복 적용을 확인했다.
- 독립 검수는 입력·제품 소스·출력의 연결과 보호 설정을 확인했다. 볼과 코 주변의 질감 완화가 관측됐으나 피부 톤·눈입·블러셔도 함께 달라지므로 피부 결함만의 개선 증거로 삼지 않는다. 확인한 고정 배경 표본은 전후 픽셀이 같았다.
- 기존 렌더의 수치와 수용 기준은 변경하지 않았다. 기존 효과·보호 검사 8개를 포함한 구현자 회귀 47개는 실패 0개이며 외부 Evoto 입력 부재 검사 1개는 생략됐다.
- 이 기록의 승인 범위는 내부 적용과 실제 상태의 연결 확인이다. 새 UI의 실행 흐름·실기기 화면과 최종 배포, 자연 촬영 사진 전반의 품질은 아직 승인하지 않았다. 옷 주름과 실제 낮·밤 재조명의 미완료 상태도 유지한다.

## 원터치 요청·결과 화면 구현자 검사 (2026-10-28)

- UI 수정본 `16bdd79`에서 빠른 보정과 뷰티 원터치가 같은 적용 보고 경로를 사용한다. 요청 강도와 실제 적용값, 개인 조정 보호와 명시적 교체를 구분한다.
- 구현자 관련 앱 검사 120개가 실패 없이 통과했다. 새 요청 흐름 8개에 드래그 한 번의 실행 취소, 보호 후 교체 및 반복 적용, 빠른 보정의 전체 대상과 뷰티 대상 분리, 사진 전환과 재분석, 강도 0의 두 동작, 저장·렌더 실패와 몸 밝기만 바뀐 안내를 포함한다.
- 합성 검사 입력의 피부 값 기대치 한 곳은 약 0.04의 부동소수점 표현 차이 때문에 실패했다. 의미값 0.04와 매우 작은 계산 오차 범위로 정정했으며 강도 0·1과 저장·실행 취소의 정확한 조건, 기존 효과·보호 기준은 유지했다.
- iOS UI 검사 타깃은 빌드만 완료했고 아직 실행하지 않았다. Mac Release 빌드는 통과했으며 검사 전용 시작 인자와 계측 문자열이 결과 바이너리에 없음을 확인했다.
- 이 절은 구현자의 고정본 인계 기록이다. 독립 UI 검수·실기기 실행·배포 완료로 해석하지 않는다.

- 후속 독립 검수에서 첫 UI 고정본의 연속 조작 결함을 재현했다. 강도 0을 고른 뒤 개인 교체를 누르면 기본 적용이 먼저 전체·그룹·몸 피부 값을 지우고 실행 취소가 두 단계 생겼다. 독립 검사 1개에서 단언 5개가 실패해 UI 승인을 보류했다.
- 원터치 강도 입력은 드래그 종료까지 사진을 바꾸지 않고, 기본 또는 개인 교체 버튼에서만 한 번 적용하도록 설계를 정정했다. 기존 실패 반례의 재검수와 실제 화면 확인 전에는 수정 완료로 판단하지 않는다.
- 수정본 `f64d076`에서 구현자 관련 검사 124개와 요청·렌더 불변을 강화한 검사 12개가 통과했다. 독립 검수도 이전 실패 반례를 바꾸지 않고 다시 실행해 통과했으며, 관련 30개 검사가 실패 없이 완료됐다.
- 독립 검수는 별도 합성 세션을 사용하는 화면 검사 소스까지 승인했다. 실제 서명된 검증 앱과 지정 기기 연결, 화면 실행 및 최종 배포 검수는 별도로 남아 있다.

## 원터치 실기기 첫 검사와 전체 검사 후속 (2026-10-28)

- 검수한 별도 QA 앱을 기존 승인된 iPhone 15 Pro에 설치했다. 실행 시 실제 잠금 오류가 나와 사용자에게 해제를 요청했고, 같은 대기 실행에서 검사를 진행했다. 사용자 사진과 편집 설정을 조회하거나 바꾸지 않았다.
- 실제 화면 검사 3개 중 상세 보정·빈 그룹·대상 분리와 빠른 보정·개인 교체·비교·되돌리기 2개가 통과했다. 강도 0 선택 검사는 요청값이 0이 되기를 기다리는 단계에서 실패했다. 개인 교체 실행 전의 실패다.
- 실패 영상에서 슬라이더가 하단 고정 메뉴에 가려져 있었고 드래그 좌표도 해당 위치와 일치했다. 정확한 실패 시점의 내부 값은 보존되지 않아 제품 문제를 완전히 배제한 것으로 판단하지 않는다. 완전 노출과 실패 전 수치·화면 기록을 보강해 재검사한다.
- 독립 검수는 첨부 17개와 상태 기록 7개를 확인했다. 상세 보정의 완료 문구·빈 그룹 초기화·대상 분리는 같은 제품 앱에서 재사용할 수 있지만, 빠른 보정의 결과 문구와 교체 버튼은 별도로 완전히 보이는 화면이 필요하다. 후속 실행은 강도 0 흐름과 빠른 보정 두 검사로 좁힌다.
- 작업 브랜치 전체 검사 [40639217012](https://github.com/MJ-0701/mellow-photo/actions/runs/40639217012)는 패키지 588개 중 생략 3개·실패 1개로 중단됐다. 앱·UI 검사와 Release 빌드는 이 실행에서 수행되지 않았다.
- 실패는 마스크 캐시의 초기 개수를 1개로 고정한 단언이었다. 독립 재현에서도 같은 단언이 실패했지만 기존 축출 후 0개 조건은 통과했다. 추가 수명 검사에서 새 준비 과정의 6개 캐시가 미리보기에서 더 늘지 않고, 축출 후 0개가 되며 외부 참조 해제 후 객체가 사라지는 것을 확인했다.
- 이 근거로 초기 개수의 가정만 실제 마스크 존재·용량·재사용을 확인하도록 정정한다. 축출 후 0개와 기존 효과·보호 기준은 유지하며 제품의 캐시 처리 자체를 바꿀 근거는 발견하지 못했다.
- 테스트만 수정한 `3ccfb35`에서 구현자와 독립 검수자의 관련 검사 3개가 각각 통과했다. 준비된 캐시가 존재하고 기존 용량 안에 있으며 미리보기에서 재사용되는지 확인하고, 축출 후 0개 조건을 그대로 유지했다.
- 같은 iPhone 화면 크기의 시뮬레이터 첫 재검사에서는 강도 0 드래그가 실제로 약 0.062에서 끝났고, 원본 비교 버튼의 위치 검사가 화면 상단에 임의로 추가한 여백 때문에 실패했다. 강도 입력 중 편집값·저장·실행 취소·미리보기는 변하지 않았다. 실패 기록과 실제 값을 보존했다.
- 검사 도구만 수정한 `1e41a54`는 실제 보이는 영역을 기준으로 버튼을 확인하고, 하단 고정 메뉴를 피하면서 한 번의 드래그로 슬라이더의 정확한 끝점에 도달한다. 제품 소스는 독립 검수한 `f64d076`과 동일하며 0을 근삿값으로 허용하거나 값을 직접 주입하지 않았다.
- 같은 시뮬레이터의 두 재검사가 실패 없이 통과했다. 강도 0 선택 43.488초와 빠른 보정 33.761초이며, 독립 검수자가 첨부 65개의 연결과 정확한 0·입력 중 무변경·개인 교체·기존 초기화·완료 문구·비교·되돌리기를 확인했다. 합성 사진으로 실행한 화면 연결 검사이므로 자연 촬영 사진의 품질 근거로 사용하지 않는다.
- 알려진 검사 도구 실패가 남아 있던 원격 실행 40641389558은 취소했다. 이를 통과로 집계하지 않으며 수정본의 원격 전체 검사와 실기기 두 재검사를 별도로 진행한다.
- 같은 승인된 iPhone 15 Pro에서 두 재검사가 실패 없이 완료됐다. 정확한 강도 0·개인 교체·되돌리기·별도 기존 초기화는 59.240초, 빠른 보정의 보호·교체·문구 노출·원본 비교·되돌리기는 52.743초다. 사용자 잠금 해제 후 기존 대기 실행 한 건을 이어갔고 중복 실행하지 않았다.
- 독립 검수자는 원결과와 첨부 69개의 해시·화면·상태를 대조해 두 흐름을 승인했다. 제품 소스가 동일하므로 앞서 통과한 상세 보정·빈 그룹·대상 분리 검사도 재사용할 수 있다. 적용값과 저장·렌더·한 단계 실행 취소의 연결을 확인한 합성 UI 세 흐름의 수용이며 자연 촬영 사진 전반의 품질 승인과 구분한다.
- 실기기 실행을 소유한 호스트·기기 프로세스는 종료됐다. 전체 원격 검사와 최종 배포 결과는 별도로 확인한다.
- 독립 판독 후 별도 QA 앱 두 개와 전용 시뮬레이터를 삭제했다. 임시 프로젝트는 원증거와 복원 정보를 보존하는 제외 폴더로 옮겼다. 사용자 앱·사진·설정은 변경하지 않았으며 검사 소유 서비스는 남아 있지 않다.

## 원터치 수정본 전체 검사 (2026-10-28)

- 제품·검사 고정본 `1e41a54`의 [Apple checks 40642520303](https://github.com/MJ-0701/mellow-photo/actions/runs/40642520303)이 성공했다. 모듈 경계·엄격한 서식·생성 프로젝트 일치·출시 안내 검사와 iOS·Mac 서명 없는 Release 빌드도 통과했다.
- 패키지 588개 중 실패 0개·생략 3개다. 생략은 기존 Evoto 외부 입력 미설정, 다문 입 데모의 치아 측정 조건과 해당 검사 기계의 인물 인스턴스 마스크 미지원이다. 수용 기준을 낮추거나 실패 검사를 생략한 결과가 아니다.
- iPhone 앱 166개·iPad 앱 166개·Mac 앱 167개·iPhone UI 7개가 모두 실패 없이 통과했다. UI의 실제 소요 시간은 355.629초이며 제품 반응 시간으로 해석하지 않는다.
- 실제 iPhone 합성 UI 수용·사용자 원본의 로컬 저장 상태 재현과 이 전체 검사의 범위를 함께 유지한다. 제품 소스는 실기기 독립 검수 후 바꾸지 않았다. TestFlight 업로드·처리와 Mac 설치 완료는 별도로 확인한다.

## 주 원터치 버튼의 개인 조정 선택 (2026-10-29)

- 사용자는 후속 확인에서도 ‘원터치 보정’만 눌렀다고 답했다. 기존 개인 값을 유지하는 기본 동작과 별도 교체 버튼 사이의 접근 문제를 수정했다. 보정 엔진의 효과 증가나 자연 사진의 품질 개선으로 표시하지 않는다.
- 기존 실제 AppModel 진입 경로에서 개인 강도 0.2·몸 밝기 0·요청 강도 1을 고정했다. 선택 전 무변경 검사 1개에서 단언 5개가 실패했으며 몸 밝기 0→0.08, 저장 5→6, 실행 취소 1→2와 화면 갱신 시작을 확인했다. 독립 검수자가 고정 소스·로그와 같은 반례를 확인했다.
- 수정본 `b5ca229`는 전체·그룹 원터치에 보호되는 개인 항목이 있으면 같은 상태의 두 적용 계획을 먼저 보여 준다. 선택 전·취소는 사진과 기록을 바꾸지 않고, 유지와 개인 교체를 선택한 뒤에만 해당 계획을 한 번 적용한다. 강도 0과 개인 직접 적용의 기존 의미는 유지한다.
- 강도·사진·대상·분석·문서 변경과 A→B→A 이후의 이전 선택을 거절한다. 선택 화면 자동 닫힘에 안내가 없던 추가 반례도 실패 기록을 남긴 뒤 수정했다. 원인과 다른 테스트 입력의 요청 강도 누락도 별도 실패로 보존했으며 원 최초 반례와 수용 기준은 변경하지 않았다.
- 구현자 관련 앱 검사 152개가 실패 없이 통과했다. 모듈 경계·엄격한 서식·생성 프로젝트 일치와 iOS UI 타깃 빌드도 통과했다. 독립 정적 검수는 제품 12개·소스 197개 연결, 최초 반례의 본문 동일, 렌더·도메인 코어와 원 수용 테스트의 변경 없음, 문서 계약을 확인했다.
- iPhone 15 Pro 화면 크기의 iOS 27 시뮬레이터에서 합성 사진의 실제 화면 검사 5개가 실패·생략 없이 통과했다. 상세 보정·빈 그룹·대상 분리, 정확한 강도 0과 두 해제 방식, 주 버튼의 선택 창·취소·스와이프 닫기·개인 교체, 빠른 보정의 유지·비교·되돌리기를 확인했다.
- 화면 검사 총 233.928초와 첨부 155개를 보존했다. 이 시간은 제품 반응 시간이 아니다. 실제 사용자 iPhone이나 개인 사진·설정에 접근하지 않았으며 전용 시뮬레이터와 검사 소유 프로세스는 종료했다. 이전 사용자 원본과 좁힌 설정의 임시 파일은 현재 없어 이번 원본 재현으로 주장하지 않는다.
- 독립 검수자가 격리 Mac에서 핵심 회귀 12개를 직접 실행해 실패 0개를 확인했다. 첫 실행의 캐시 접근 제한은 검사 실행 전 환경 실패로 보존했으며, 후속 정상 실행은 9.000초다. 원 최초 반례의 본문은 같은 상태로 통과했다.
- 독립 화면 검수는 원 첨부 155개와 완료 상태 20개의 연결, 선택 전·취소·스와이프 닫기의 무변경, 개인 교체와 한 번의 되돌리기, 유지 후 변경 없음, 두 강도 0 동작과 원본 비교를 확인했다. 선택 창과 두 경로의 결과·비교·되돌리기 버튼이 보이는 화면을 직접 판독했다. 몸 밝기만 바뀌는 유지 선택은 화면 검사가 아닌 모델 회귀의 근거로 구분한다.
- 주 버튼 선택 UX의 독립 수용은 통과했으며 구현자와 검수자 소유 서비스는 모두 종료됐다. 원격 전체 검사·최종 배포와 사용자 피부 품질 수용은 별도다. 옷 주름의 효과 22개 실패·미채택 및 실제 낮·밤 재조명 미완료 상태를 유지한다.

## 주 원터치 배포 검사 환경 복구 (2026-10-29)

- `ff85a04`의 [전체 검사 40789531986](https://github.com/MJ-0701/mellow-photo/actions/runs/40789531986)은 패키지 588개(기존 생략 3개), iPhone·iPad 각 178개, Mac 179개, UI 9개가 실패 없이 통과했고 서명 없는 Release 빌드도 성공했다. 최종 소스와 로그를 독립 대조했다.
- 같은 소스의 [배포 실행 40789532980](https://github.com/MJ-0701/mellow-photo/actions/runs/40789532980)은 앱 검사까지 통과했지만 UI 9개 중 3개가 실패했다. 패키지 생성·업로드는 수행되지 않았다. 실패 기록과 원결과를 보존하고 성공한 별도 실행으로 덮어 판정하지 않는다.
- 실패 실행은 iPhone 16 Pro 시뮬레이터·iOS 18.5였다. 두 진입 실패에서 앱 종료 시각·PID와 `libRPAC`의 `interposed_dispatch_group_wait` 내부 SIGSEGV를 독립 연결했다. 첫 상세 보정 검사는 교체 완료 화면·상태 뒤 실행 취소 중 화면 조회가 멈췄으며, 같은 원인이라고 확정하지 않았다.
- 기존 생성 후 처리 스크립트는 이 성능 진단 도구의 충돌 방지 설정을 일반 앱 검사에만 적용했다. `5cc94d5`는 명시된 두 scheme의 TestAction에 같은 정책을 적용하며 제품 코드·앱 실행 설정·수용 문턱·단언·대기 시간은 변경하지 않는다.
- 고정된 설정 회귀 6개에서 기존 소스는 5개 실패, 수정본은 실패 0개를 구현자와 검수자가 각각 확인했다. 두 파일을 모두 사전 확인한 뒤 쓰며 누락·중복·잘못된 값은 거절한다. 반복 적용과 LaunchAction 보존을 확인했고, 구현자의 고정 XcodeGen 두 번 재생성 결과도 같은 파일 해시였다.
- 이 판정은 검사 환경 패치의 수용이다. 첫 실행 취소 후 멈춤의 해결이나 배포 완료를 의미하지 않으며, 수정한 최종 소스의 전체 검사와 배포 검사를 다시 통과해야 한다. 실패 태그는 이동하지 않고 새 main의 1.6.2 TestFlight 배포 실행을 별도로 식별한다.
