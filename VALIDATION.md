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
