# 후속 버전 변경사항

첫 1.0.0 심사 빌드에는 이 설정을 적용하지 않습니다. 이미 공개된 iOS 버전이 있을 때, 다음 배포 버전 이름의 JSON 파일을 이 폴더에 커밋하세요. 예를 들어 `apple-v1.0.1` 태그는 `1.0.1.json`을 읽습니다.

형식 예시만 다음과 같습니다. 실제 변경사항으로 작성해야 하며, 이 예시는 배포 파일이 아닙니다.

```json
{
  "ko": "이번 버전에서 사용자가 확인할 수 있는 실제 변경사항을 적습니다."
}
```

App Store Connect 버전의 모든 언어 코드를 정확히 포함해야 합니다. 현재 한국어 코드는 `ko`입니다. 언어를 추가한 경우 해당 언어의 변경사항도 작성하세요. 각 값은 공백만 있으면 안 되고 4,000자 이하여야 합니다.

배포 단계는 다음과 같습니다.

1. 실제 앱 수정과 해당 버전 JSON을 함께 커밋하고 main에 push합니다.
2. CI 통과와 변경사항을 확인합니다.
3. `scripts/release.sh apple X.Y.Z`로 `apple/Config/Version.xcconfig`의 버전을 올려 커밋하고 `apple-vX.Y.Z` 태그를 만든 뒤 `git push origin main apple-vX.Y.Z`로 push합니다. `.github/workflows/apple-release.yml`이 실행됩니다.
4. CI는 기존 live/editable 버전을 읽어 notes 누락·형식·언어를 서명 archive 전에 검증합니다.
5. fastlane이 새 editable 버전을 생성/선택한 후 JSON을 해당 버전의 What's New 필드에만 반영합니다.
6. 설정된 자동화 정책에 따라 빌드를 심사 제출하고, Apple 승인 후 공개합니다.

다른 번호의 editable 버전이 이미 있거나 공개된 버전 번호를 재사용하면 중단합니다. 기존 심사 버전 이름을 자동으로 바꾸지 않습니다. 새 버전의 언어 목록이 예상과 달라진 경우에도 변경사항을 쓰기 전에 중단합니다.

이 경로는 설명·스크린샷·심사 연락처·개인정보·가격을 덮어쓰지 않습니다. 새 기능에 따라 해당 정보 수정이 필요하면 별도로 완료해야 하며, Apple 심사나 계정 약관으로 인한 차단을 우회하지 않습니다. 처음부터 새 버전용 스크린샷을 만들어주는 기능은 아닙니다.

검증: `/usr/bin/ruby fastlane/test/release_notes_test.rb`

구현 근거는 고정된 fastlane 2.238.0 소스입니다.

- [Runner의 버전 확인은 metadata skip과 독립](https://github.com/fastlane/fastlane/blob/2.238.0/deliver/lib/deliver/runner.rb)
- [skip_metadata가 release_notes 읽기·쓰기까지 건너뛰는 동작](https://github.com/fastlane/fastlane/blob/2.238.0/deliver/lib/deliver/upload_metadata.rb)
- [ensure_version!의 기존 버전 수정 또는 새 버전 생성](https://github.com/fastlane/fastlane/blob/2.238.0/spaceship/lib/spaceship/connect_api/models/app.rb)
- [localized whats_new 업데이트 API](https://github.com/fastlane/fastlane/blob/2.238.0/spaceship/lib/spaceship/connect_api/models/app_store_version_localization.rb)
