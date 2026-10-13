# iPhone 정식 출시와 자동 배포

현재 소스에는 iPhone 앱과 GitHub Actions 배포 경로가 들어 있습니다. 2026-10-13 개인 개발자 계정 활성화, 인증서·프로필, App Store Connect 앱 등록과 GitHub 자격증명 연결을 완료했습니다. 서명 업로드·스토어 자료·심사 제출 결과는 별도로 확인해야 하며, CI 구성만으로 출시 완료나 Apple 심사 승인을 의미하지 않습니다.

## 연결 현황 (2026-10-13)

- 비공개 저장소 `MJ-0701/mellow-photo`, 배포 환경 `production`.
- 환경 배포 허용 대상: `main` 브랜치와 `ios-v*` 태그.
- 아래 일곱 Secrets 모두 저장 완료. Apple ID 비밀번호는 저장하지 않았습니다.
- 첫 업로드는 심사 제출·자동 공개를 끈 수동 실행으로 진행했습니다. 이후 사용자가 후속 태그의 자동 심사 제출과 승인 후 자동 공개를 명시적으로 승인해, `IOS_RELEASE_ENABLED`, `IOS_AUTO_SUBMIT`, `IOS_AUTO_RELEASE` 세 repository variables를 모두 `true`로 설정했습니다. 이미 올라간 최초 버전 1.0.0은 수동 공개로 유지합니다.
- App Store 앱 ID `6822201639`, bundle ID `com.mj.mellowphoto`.
- 첫 실행 `38367871570`은 테스트 통과 후 서명 준비 단계에서 실패했습니다. PKCS#12 파일을 macOS 호환 형식으로 다시 묶고 Apple WWDR G3 중간 인증서를 포함했습니다. 기존 인증서·개인키·프로필의 일치를 유지하며 임시 키체인의 import, partition, 유효한 서명 identity 검증을 통과한 뒤 P12 Secret 하나만 갱신했습니다.
- [첫 성공 실행 38369395464](https://github.com/MJ-0701/mellow-photo/actions/runs/38369395464): 버전 1.0.0 / 빌드 4.1. 테스트, 서명 archive·IPA export, 두 bundle의 서명·버전·entitlement 검증, App Store Connect 업로드와 임시 자료 정리가 모두 통과했습니다. Fastlane의 IPA 업로드 호출과 빌드 선택 전용 호출에서 충돌하는 옵션도 분리했습니다. Apple의 최종 심사 결과는 이 실행 성공에 포함되지 않습니다.
- 2026-10-13 17:35 KST, 1.0.0 (4.1)을 정식 심사에 제출했고 **심사 대기 중**을 확인했습니다. [제출 상세](https://appstoreconnect.apple.com/apps/6822201639/distribution/reviewsubmissions/details/75504532-3e29-4067-95e2-bf92fda3ed75). 최초 버전은 승인 후 수동 공개입니다.
- 배포 성공과 심사 접수 후 로컬의 임시 개인키·P12·암호·API 키 파일은 정리했습니다. GitHub production Secrets와 Apple 인증서/API 키 등록은 유지합니다.

## 자동화 범위

- main push/PR: 보정 엔진 회귀 테스트와 iPhone 시뮬레이터 XCTest, 최적화된 unsigned Release iPhone 빌드. arm64 실행 파일, 앱 bundle ID, iPhoneOS 플랫폼, asset catalog, 개인정보 manifest 포함 여부도 확인합니다. 인증서가 없어도 이 단계까지 실행할 수 있습니다.
- 시뮬레이터 테스트 결과는 고유 경로의 xcresult로 남기며, 실패 시 GitHub Actions artifact에 7일간 보관합니다. 실패 로그·테스트 결과는 실기기/실사용자 사진으로 만든 자료가 아닌 CI 테스트 자료만 담아야 합니다.
- `ios-v1.0.0` 같은 태그: 동일 테스트 → 서명된 archive/IPA 생성 → 서명·bundle·버전 검증 → App Store Connect 업로드.
- 기본값은 업로드까지만. 심사 제출과 승인 후 자동 공개는 별도로 켤 수 있습니다.
- Apple 심사, 계정 약관, 개인정보/수출 관련 응답은 자동으로 생략하거나 통과할 수 없습니다.
- GitHub Actions 사용량/요금은 계정 플랜을 따릅니다. 이 저장소는 macos-15와 Xcode 26.3을 명시합니다. runner에서 해당 버전 제거 시 함께 업데이트하세요.

한글 스토어 설명과 영문 심사 안내 초안은 [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md) 및 `fastlane/metadata/`에 있습니다. 현재 파이프라인은 이 메타데이터를 자동 업로드하지 않습니다.

## 최초 한 번 필요한 설정

1. Apple Developer 멤버십이 Active인지 확인하고 Team ID를 확인합니다.
2. Apple Developer에서 명시적 App ID `com.mj.mellowphoto`를 등록합니다. 이미 다른 계정에 속해 있다면 Xcode 프로젝트와 Fastfile의 bundle ID를 함께 바꿉니다.
3. App Store Connect에 iOS 앱 레코드를 만들고 해당 bundle ID를 선택합니다. 인증서 private key가 포함된 Apple Distribution `.p12`와 이 앱의 **App Store Connect distribution provisioning profile**을 준비합니다. Development/Ad Hoc/Enterprise 프로필은 거부합니다.
4. App Store Connect Users and Access → Integrations에서 **team API key**를 준비합니다. 이 파이프라인은 Issuer ID가 있는 team key를 사용하며, 업로드와 심사 제출에 필요한 App Manager 역할/앱 접근을 지정합니다.
5. GitHub 저장소 Settings → Environments에 `production`을 만들고 아래 secrets를 저장합니다. 자격증명은 채팅이나 git에 붙여넣지 않습니다.
6. 최초 출시는 실제 iPhone에서 사진 선택/보정/저장/메모리/권한 거부를 검증하고 스크린샷, 소개, 지원 URL, 공개 개인정보 처리방침 URL, 연령 등급, 개인정보 응답, 심사 연락처, 국가/가격을 App Store Connect에서 완성합니다. 현재 앱의 기능에 맞는 설명을 사용하고 Evoto와 동일한 AI 성능을 주장하지 않습니다.
7. 준비가 끝나면 **repository variable** `IOS_RELEASE_ENABLED=true`로 배포 job을 켭니다. 기본 미설정 상태에서는 release job을 건너뜁니다. CI 테스트에는 이 변수와 Apple secrets가 필요 없습니다.

### production 환경 secrets

| 이름 | 내용 |
|---|---|
| `APPLE_TEAM_ID` | Apple Team ID 10자리 |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | Team API issuer UUID |
| `ASC_KEY_BASE64` | `.p8` 파일의 줄바꿈 없는 base64 |
| `DISTRIBUTION_P12_BASE64` | private key 포함 `.p12`의 줄바꿈 없는 base64 |
| `DISTRIBUTION_P12_PASSWORD` | `.p12` 암호, 비어 있지 않은 값 |
| `APPSTORE_PROFILE_BASE64` | `.mobileprovision`의 줄바꿈 없는 base64 |

PKCS#12를 직접 만들 때 최신 OpenSSL의 기본 PBES2/AES 포맷은 macOS `security import`에서 인증 오류를 낼 수 있습니다. 이 설정은 기존 인증서·개인키와 공식 WWDR G3 중간 인증서를 3DES/SHA-1 MAC 호환 P12로 묶어 검증했습니다. 이는 암호가 걸린 전송용 컨테이너 포맷이며 앱 서명 키나 인증서 알고리즘을 변경하지 않습니다. 로컬 파일은 제한된 권한으로 보관하고, 반드시 임시 키체인의 실제 import와 유효한 identity를 확인한 뒤 Secrets를 갱신하세요. 원본 비밀키와 암호를 로그에 출력하지 마세요.

Mac에서 파일을 변환하려면 `base64 -i /path/to/file | tr -d '\n' | pbcopy`로 클립보드에 복사한 후 GitHub Secret 입력란에 붙여넣습니다. 작업 후 클립보드를 지웁니다. 이메일/Apple ID 암호는 CI에 필요 없습니다.

`production` 환경에 required reviewer를 설정하여 첫 공개 승인 단계를 두는 것을 권장합니다. 환경 이름만 YAML에 작성하는 것으로 승인이 강제되지는 않습니다. **비공개 저장소의 required reviewer 지원은 GitHub 플랜에 따라 제한됩니다.** 사용할 수 없는 플랜에서는 심사 제출/자동 공개 변수를 끈 채 App Store Connect에서 직접 제출·공개합니다. 태그 배포와 workflow_dispatch에 허용할 ref도 환경 배포 규칙으로 제한하세요. 현재 연결 현황은 위 기록을 따르며, 이 문서 자체는 원격 설정을 변경하지 않습니다.

## 첫 업로드

GitHub Actions → `iOS App Store release` → Run workflow에서 `version=1.0.0`, `submit_for_review=false`, `automatic_release=false`로 실행합니다. 처음에는 App Store Connect에서 처리 완료된 빌드를 확인한 다음 직접 심사 제출하는 것이 좋습니다. 인증서/프로필 만료, 계정 활성화 지연, 약관 미동의는 정상적인 차단 원인이며 CI가 우회하지 않습니다.

빌드 번호는 `github.run_number.github.run_attempt`로 자동 증가합니다. 같은 실행의 재시도도 다른 번호를 사용합니다. 수동으로 더 높은 빌드 번호를 이미 올렸다면 이후 번호 충돌을 피하도록 규칙을 조정해야 합니다. 공개된 버전을 업데이트할 때는 새로운 앱 버전 번호를 사용합니다.

## 첫 출시 이후

실제 변경사항을 `fastlane/release_notes/1.0.1.json`처럼 버전별 파일로 작성해 앱 수정과 함께 main에 push합니다. 현재 언어는 `ko`이며 [형식과 검증 규칙](../fastlane/release_notes/README.md)을 따릅니다. CI 통과 후 다음 태그를 push합니다.

```sh
git tag ios-v1.0.1
git push origin ios-v1.0.1
```

현재는 사용자의 명시적 승인에 따라 아래 세 변수가 모두 `true`입니다. 태그 배포는 테스트, 서명, 업로드, 해당 버전 변경사항 반영, 심사 제출, Apple 승인 후 자동 공개까지 진행합니다. 최초 1.0.0의 공개 설정은 별도로 수동을 유지했습니다.

| 변수 | `true`일 때 |
|---|---|
| `IOS_RELEASE_ENABLED` | 배포 job 실행 허용 |
| `IOS_AUTO_SUBMIT` | 태그 빌드를 업로드한 뒤 Apple 심사 제출 |
| `IOS_AUTO_RELEASE` | Apple이 승인한 뒤 자동 공개 |

수동 실행은 위 두 AUTO 변수 대신 입력 체크박스를 사용합니다. `automatic_release`는 `submit_for_review=true`와 함께 사용하세요. 심사 거절 시 수정 후 새 빌드를 올려야 합니다.

기존 스토어 설명·스크린샷·심사 연락처·개인정보는 유지하고, 버전별 JSON에서 해당 버전의 What's New만 갱신합니다. 변경사항이 없거나 언어가 일치하지 않거나 다른 편집 중 버전이 있으면 archive 전에 중단합니다. 새 기능으로 개인정보·소개·스크린샷 등의 변경이 필요하면 해당 자료도 제출 전에 갱신해야 합니다. 후속 버전 경로는 고정 fastlane 소스 대조와 독립 검수, 로컬 테스트 6개/검증 항목 18개를 통과했으나 실제 두 번째 버전의 업로드·제출·자동 공개를 실행한 것은 아닙니다.

서명 파일은 임시 runner 폴더와 임시 keychain에서만 사용하고 성공·실패 시 정리합니다. IPA/인증서를 Actions artifact로 공개하지 않습니다. GitHub-hosted runner에서만 실행하도록 구성했으며 self-hosted runner 전환 시 정리 정책을 다시 검토해야 합니다.

## 검증 현황과 출처

로컬에서 Ruby/YAML 정적 검사를 수행할 수 있지만 실제 서명·업로드는 유효한 Apple 자격증명과 Xcode가 필요합니다. 성공한 release workflow와 App Store Connect 처리 결과를 확인하기 전에는 배포 검증 완료로 표시하지 않습니다.

- [Apple: 앱 심사 제출](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [GitHub: macOS runner 서명 인증서 설치](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub: 배포 환경과 보호 규칙](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub: macos-15 설치 도구 목록](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [fastlane: App Store 배포](https://docs.fastlane.tools/getting-started/ios/appstore-deployment/)
- [fastlane: build_app](https://docs.fastlane.tools/actions/build_app/)
- [fastlane: App Store Connect API key](https://docs.fastlane.tools/actions/app_store_connect_api_key/)
