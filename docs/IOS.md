# iPhone 앱

아이폰용 네이티브 SwiftUI 앱. iOS 17 이상, iPhone 전용입니다. Mac 앱과 `MellowCore`를 공유하고, Apple PhotosPicker로 선택한 사진만 작업 사본으로 가져옵니다.

## 준비 및 실행

1. Xcode 전체 버전과 iOS 플랫폼/시뮬레이터를 설치합니다. Command Line Tools만으로는 iOS를 빌드할 수 없습니다. 현재 App Store 제출에는 Xcode 26 / iOS 26 SDK 이상이 필요합니다.
2. `iOS/MellowPhoto.xcodeproj`를 열고 `MellowPhotoIOS` 스킴을 선택합니다.
3. 시뮬레이터를 선택해 실행합니다. 실제 iPhone은 Xcode의 Signing & Capabilities에서 본인 Team을 고른 뒤 연결합니다. 유료 개발자 활성화와 서명은 소스 구현과 별도입니다.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/build-ios.sh simulator
xcrun simctl list devices available
MELLOW_SIMULATOR_ID='<iPhone simulator UUID>' ./scripts/build-ios.sh test
```

## 사용

- `+`로 사진 최대 12장을 선택합니다. HEIC/JPEG/PNG 등의 정지 사진을 처리합니다. iCloud에만 있는 원본은 가져오는 동안 네트워크가 필요할 수 있습니다. 보정은 기기 내부에서 처리합니다.
- 색감 프리셋, 노출·대비·채도·따뜻함을 조정합니다.
- 얼굴 형태를 먼저 조정한 뒤 잡티나 부분 변형을 사용하세요. 수동 작업이 있으면 얼굴 형태·대상 선택은 좌표 보호를 위해 잠깁니다.
- 잡티: 깨끗한 부분을 샘플로 한 번 탭한 뒤 보정할 부분을 탭합니다. 변형: 필요한 부분을 조금 드래그합니다.
- 우측 위 저장 메뉴로 현재 사진 또는 전체 사진을 사진 앱에 새 파일로 저장합니다. 최초 저장 때 사진 추가 권한을 요청합니다.
- 기본 출력은 긴 변 최대 4096px, 8bit sRGB SDR JPEG입니다. 원본 해상도를 켜면 메모리 사용량이 크게 늘 수 있습니다. HDR·ProRAW·Live Photo 영상 보존은 지원하지 않습니다.
- 작업 사진 사본, 보정 기록, 실행 취소·복귀 기록, 프리셋은 앱 내부에 저장합니다. 작업 폴더는 기기 백업에서 제외합니다. 앱 삭제 시 사라지므로 완성한 사진을 사진 앱에 저장하세요.
- ‘편집에서 사진 빼기’는 앱 내부 사본만 삭제합니다. 사진 앱의 원본은 변경하거나 삭제하지 않습니다.
- 백그라운드 전환 시 일괄 저장은 현재 사진 이후 중단됩니다. 저장을 다시 누르면 새 사본이 추가되므로 중복 저장에 주의하세요.

## 검증 상태

Mac 공유 엔진 GPU 테스트 8개 통과. iOS Swift 문법 검사, 프로젝트 plist 검사 통과. GitHub Actions에서 Xcode 26.3 / iOS 18.5 시뮬레이터 빌드와 XCTest 4개가 통과했습니다(2026-10-13). 로컬 실기기 테스트와 사진 권한 화면 검증은 아직 미실시했습니다.

기기에서 반드시 확인할 항목: 최초 권한 허용/거절, HEIC 및 방향 회전, iCloud 사진 가져오기, 얼굴 0/1/여러 명, 잡티·변형 후 실행 취소, 재실행 복원, 전체 사진 저장, 48MP 메모리, 작은 화면과 큰 글자, 백그라운드 전환. 현재 핀치 확대는 미구현입니다.

App Store 자동화는 [IOS_RELEASE.md](IOS_RELEASE.md)를 참조하세요. App Store 심사에 필요한 실제 스크린샷, 공개 지원·개인정보 URL, 등급·배포 정보는 첫 제출 전에 완성해야 합니다.

공개 지원: https://mj-0701.github.io/mellow-photo-support/
개인정보 안내: https://mj-0701.github.io/mellow-photo-support/privacy.html
