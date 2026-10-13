# iPhone 정식 출시와 자동 배포

현재 소스에는 iPhone 앱과 GitHub Actions 배포 경로가 들어 있습니다. 개발자 결제 완료와 Apple 계정 활성화는 다릅니다. 계정 활성화, 인증서, App Store Connect 앱 등록, 실기기 검증, 스토어 자료를 완료해야 출시할 수 있습니다. CI 구성만으로 출시 완료나 Apple 심사 승인을 의미하지 않습니다.

## 자동화 범위

- main push/PR: 보정 엔진 회귀 테스트와 iPhone 시뮬레이터 XCTest.
- `ios-v1.0.0` 같은 태그: 동일 테스트 → 서명된 archive/IPA 생성 → 서명·bundle·버전 검증 → App Store Connect 업로드.
- 기본값은 업로드까지만. 심사 제출과 승인 후 자동 공개는 별도로 켤 수 있습니다.
- Apple 심사, 계정 약관, 개인정보/수출 관련 응답은 자동으로 생략하거나 통과할 수 없습니다.
- GitHub Actions 사용량/요금은 계정 플랜을 따릅니다. 이 저장소는 macos-15와 Xcode 26.3을 명시합니다. runner에서 해당 버전 제거 시 함께 업데이트하세요.

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

Mac에서 파일을 변환하려면 `base64 -i /path/to/file | tr -d '\n' | pbcopy`로 클립보드에 복사한 후 GitHub Secret 입력란에 붙여넣습니다. 작업 후 클립보드를 지웁니다. 이메일/Apple ID 암호는 CI에 필요 없습니다.

`production` 환경에 required reviewer를 설정하여 첫 공개 승인 단계를 두는 것을 권장합니다. 환경 이름만 YAML에 작성하는 것으로 승인이 강제되지는 않습니다. **비공개 저장소의 required reviewer 지원은 GitHub 플랜에 따라 제한됩니다.** 사용할 수 없는 플랜에서는 심사 제출/자동 공개 변수를 끈 채 App Store Connect에서 직접 제출·공개합니다. 태그 배포와 workflow_dispatch에 허용할 ref도 환경 배포 규칙으로 제한하세요. secrets와 변수는 아직 이 코드에서 원격 설정하지 않습니다.

## 첫 업로드

GitHub Actions → `iOS App Store release` → Run workflow에서 `version=1.0.0`, `submit_for_review=false`, `automatic_release=false`로 실행합니다. 처음에는 App Store Connect에서 처리 완료된 빌드를 확인한 다음 직접 심사 제출하는 것이 좋습니다. 인증서/프로필 만료, 계정 활성화 지연, 약관 미동의는 정상적인 차단 원인이며 CI가 우회하지 않습니다.

빌드 번호는 `github.run_number.github.run_attempt`로 자동 증가합니다. 같은 실행의 재시도도 다른 번호를 사용합니다. 수동으로 더 높은 빌드 번호를 이미 올렸다면 이후 번호 충돌을 피하도록 규칙을 조정해야 합니다. 공개된 버전을 업데이트할 때는 새로운 앱 버전 번호를 사용합니다.

## 첫 출시 이후

새 버전의 App Store Connect 메타데이터/변경사항을 준비한 후 다음 태그를 push합니다.

```sh
git tag ios-v1.0.1
git push origin ios-v1.0.1
```

자동 업로드 후 직접 심사 제출할 수 있습니다. 완전한 후속 자동화를 원하면 repository variables를 설정합니다.

| 변수 | `true`일 때 |
|---|---|
| `IOS_RELEASE_ENABLED` | 배포 job 실행 허용 |
| `IOS_AUTO_SUBMIT` | 태그 빌드를 업로드한 뒤 Apple 심사 제출 |
| `IOS_AUTO_RELEASE` | Apple이 승인한 뒤 자동 공개 |

수동 실행은 위 두 AUTO 변수 대신 입력 체크박스를 사용합니다. `automatic_release`는 `submit_for_review=true`와 함께 사용하세요. 최초 공개나 승인 자동화 여부는 설정자가 선택하며, 이 저장소는 기본으로 활성화하지 않습니다. 심사 거절 시 수정 후 새 빌드를 올려야 합니다.

기존 스토어 메타데이터를 자동 덮어쓰지 않도록 fastlane에 `skip_metadata`/`skip_screenshots`를 지정했습니다. 새 버전 심사에 필요한 필드가 누락되면 제출이 실패합니다. 스토어 자료까지 자동화하려면 검토 완료된 별도 메타데이터 관리가 필요합니다.

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
