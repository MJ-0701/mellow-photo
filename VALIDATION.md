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
