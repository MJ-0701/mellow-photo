# 인물 보정 H4 성별 자동 추정(Core ML) 구현 계획 — 선택, 사용자 승인 관문 있음

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Task 1이 끝나면 멈추고 사용자 승인을 받는다. 승인 없이 Task 2로 가지 않는다.**

**Goal:** H2의 `GenderEstimator` 포트에 Core ML 기본 구현을 붙여 사람 칩이 처음부터 "추정" 성별을 보이게 하고, H3의 생성 사진 라벨로 정확도를 재어 VALIDATION에 적는다. 모델은 앱 번들에 두고 앱이 주입한다.

**Architecture:** 후보 모델 비교(크기·라이선스·학습 데이터·편향 보고·Core ML 변환 가능성)를 문서로 만들어 사용자가 고른다. 고른 모델은 `.mlmodelc`로 컴파일해 앱 리소스(`apple/MellowPhoto/Resources/`)에 두고, MellowRendering `Infrastructure/CoreMLGenderEstimator`가 모델 URL을 받아 얼굴 상자를 잘라 `VNCoreMLRequest`로 분류한다. MellowRendering이 `CoreML`을 import하므로 모듈 표와 `verify-modules.sh`를 같은 커밋에서 고친다. 임계값·수동 우선 규칙은 H2 그대로이고 화면은 H3의 "추정" 표시를 그대로 쓴다.

**Tech Stack:** Core ML, Vision(`VNCoreMLRequest`·`VNClassificationObservation`), coremltools(변환이 필요할 때, 스크래치 폴더의 Python 가상환경), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md` (결정 표의 자동 추정 행, 1.1의 H4 행, 1.5, 2의 H4 행, 3의 정확도 측정, 4, 5). 선행: H1·H2·H3 계획 전부 머지.

## 사람이 확인할 것

### G4 개정 (2026-10-21)

[G4 스펙](../specs/2026-10-21-beauty-g4-one-touch-design.md) 5절에 따라 이 계획의 제약을 고쳤다. 결정은 바뀌지 않았다.

- 기준 코드: main `74fb2df`(1.3.0 (8.1) TestFlight, G 머지됨). 브랜치 `beauty-g4`(worktree를 쓰면 `.claude/worktrees/beauty-g4`). `beauty-g-evoto`·`.claude/worktrees/beauty-g`는 더 쓰지 않는다.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다**(SpringBoard 오류 창이 사용자를 방해함). `MELLOW_IOS_TESTS`를 켜지 않는다. `./scripts/test-apple.sh`는 로컬에서 iOS를 건너뛰며 iOS 검증은 CI(사용자가 요금 한도를 푼 뒤)다.
- 실행 순서: G4-1 → H3 Task 1(생성 사진) → H1 → H2 → G4-2 → H3 Task 2·3 → G4-3 → H3 Task 4 → (승인 시) H4.
- Task 1(후보 모델 조사, 문서만)은 G4-1과 병행해 미리 할 수 있다(G4 스펙 질문 3). Task 2 이후는 사용자 승인 뒤 G4-3·H3 Task 4가 끝난 다음이다.
- 원터치가 성별 표를 쓰므로 자동 추정이 들어오면 미지정 사람이 추정 성별의 표를 받게 된다(수동 지정이 늘 우선). 이 동작은 H2 `effectiveGender` 규칙 그대로이며 G4-2 `applyOneTouch(…in: .person)`은 기록의 **수동** 성별만 본다(추정은 렌더에서만 적용). VALIDATION에 이 차이를 적는다.

- **순서.** Task 1 후보 모델 조사·권고 문서 → **사용자 승인(관문)** → 2 모듈 표·스크립트·모델 번들·추정기 → 3 라벨 정확도 측정·앱 주입 → 4 VALIDATION·스토어·개인정보 검토 항목. 4개 Task.
- **외부 효과가 있는 단계.** 모델 파일 다운로드(크기 10~90 MB, 출처는 Task 1 표의 URL), 필요하면 coremltools 설치(스크래치 가상환경). 푸시·태그·TestFlight는 없다. 앱 크기가 모델만큼 는다.
- **사용자가 정해야 하는 것(Task 1 뒤).** 후보 중 하나를 고르거나 H4를 하지 않기로 한다. 라이선스·배포 조건의 최종 판단은 사용자 몫이다(에이전트는 출처 링크와 원문 인용만 제공하고 해석하지 않는다).
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 모델은 MellowRendering 패키지 리소스가 아니라 앱 리소스에 두고 URL로 주입한다(`CoreMLGenderEstimator(modelURL:)`) | `Package.swift`에 리소스를 더하지 않아도 되고 메이크업·룩 카탈로그와 같은 주입 방식. 테스트는 앱 번들 사본 경로를 직접 읽는다 | 작음 |
| 얼굴 자르기는 상자를 사방 25% 넓힌 정사각형(`genderCropMargin` 0.25), 모델 입력 크기로 Vision이 맞춘다 | 분류 모델은 보통 머리·턱을 포함한 얼굴 전체로 학습됨 | 작음 |
| 분류 라벨 → `Gender` 대응표는 모델마다 다르므로 `GenderModelLabels`(앱 `AppModel.Policy`가 아니라 Rendering `CoreMLGenderEstimator.Labels`) 한 곳에 둔다. 두 라벨 중 어느 쪽도 아니면 nil | 모델 교체 시 이 표만 바꾼다 | 작음 |
| 정확도는 "추정이 라벨과 같은 얼굴 수 / 추정을 낸 얼굴 수"와 "추정 비율"을 함께 적고, 자동 테스트는 수치를 **기록**하지 **관문**으로 쓰지 않는다 | 생성 사진 5장(약 20명)은 통계로 작다. 넣을지 말지는 VALIDATION을 보고 사용자가 정한다 | 작음 |
| `PrivacyInfo.xcprivacy`는 바꾸지 않는다(수집 없음, 기기 안 추론). 앱 설명·심사 노트 문구는 사용자 조치 항목으로만 적는다 | 데이터가 기기를 떠나지 않으므로 수집 유형이 없다. 심사 문구는 사람이 쓴다 | 작음 |

- **범위 밖.** 나이·표정 추정, 모델 미세 조정, 사진 사이 같은 사람 인식.
- **위험.** 공개 모델은 피부톤·나이·옆얼굴에서 정확도가 떨어진다는 보고가 많다. 라이선스가 비상업·연구 전용인 모델이 많아 쓸 수 없을 수 있다. 생성 사진은 실사진 분포가 아니다. 대응: Task 1 표로 먼저 거르고, 수동 지정이 늘 우선하며 "추정" 표시를 붙이고, 실사진 정확도는 사용자 확인(VALIDATION 미검증).
- **사용자 조치.** Task 1 뒤 모델 선택 또는 중단 결정. 라이선스 확인. Task 4 뒤 실사진으로 추정 결과 확인. 앱 설명·심사 노트에 "성별 추정은 기기 안에서만 이루어지고 저장·전송하지 않으며 사용자가 고칠 수 있다"를 넣을지 결정.

---

## 에이전트 참조

## Global Constraints

H1 계획의 Global Constraints를 그대로 따른다. 이 계획에서 다른 것:

- 시작 조건: H3 머지. 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**(H1 Global Constraints 참고). 이 계획이 더하는 수는 **Rendering +4, 앱 Mac +1**(Task 2 Rendering +3, Task 3 Rendering +1·Mac +1). 아래의 "Executed N tests"는 명목치(H3 끝 명목 406 → 410, Mac 85 → 86)이므로 실측 기준값에 같은 증분을 더해 읽는다.
- **Task 1 뒤 멈춘다.** 사용자가 모델을 고르면 Task 2부터 계속하고, 중단하면 이 계획은 끝이다(VALIDATION에 "H4 미수행, 자동 추정 없음"을 적는다).
- 모듈 표 변경은 Task 2 한 커밋에서 `docs/architecture/modules.md`(MellowRendering 행 import 허용에 `CoreML` 추가)와 `scripts/verify-modules.sh`(표의 값을 그대로 옮긴 배열에 `CoreML` 추가)를 함께 고친다. 다른 모듈의 허용 목록은 바뀌지 않는다.
- 다운로드한 모델·변환 스크립트·가상환경은 스크래치 폴더의 새 빈 폴더에 둔다. 스크립트는 다른 폴더에 두고 경로를 인자로 넘긴다. Python은 `python3 -I`로 실행한다. 저장소에는 컴파일된 `.mlmodelc`(또는 `.mlpackage`)와 출처 README만 넣는다.
- 모델 파일 크기는 Task 1에서 정한 상한(권고 30 MB) 이내. 넘으면 사용자에게 다시 묻는다.
- `RenderTuning` 새 상수(Task 2): `genderCropMargin` 0.25. 라벨 대응은 `CoreMLGenderEstimator.Labels`.
- 앱 파일을 더하지 않는다(모델은 리소스). `project.yml`은 `Resources/` 폴더 전체를 리소스로 잡으므로 고치지 않는다. 리소스 추가는 `xcodegen generate`가 필요하다(Task 2).
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트 명령은 H1과 같다. Core ML 추론 테스트는 macOS에서 돈다.

## Review Focus

1. **모델이 없는 기기(리소스 누락).** 추정기 생성이 nil이고 앱은 모두 미지정으로 동작해야 한다(H1~H3 상태와 같음). → Task 3 `testMissingModelMakesNoEstimatorAndEveryoneStaysUnassigned`.
2. **옆얼굴·작은 얼굴.** H2 임계값이 추정을 버려야 한다(모델이 뭘 내든). → Task 2 `testEstimatorReturnsOneEstimatePerFaceInOrder`(길이·순서)와 H2 `acceptedEstimates` 테스트가 함께 보증.
3. **라벨이 모호한 사람(`ambiguous: true`).** 정확도 계산에서 뺀다. → Task 3 `testAccuracyAgainstLabelsIsMeasuredAndReported`.
4. **수동 지정 뒤 다시 준비(재분석).** 추정이 바뀌어도 수동 지정이 남아야 한다(H2 규칙 재확인). → Task 3 같은 테스트의 마지막 단락.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowRendering/Infrastructure (Task 2)
public struct CoreMLGenderEstimator: GenderEstimator {
    public enum Labels { static let male: Set<String>; static let female: Set<String> }   // Task 1에서 고른 모델의 출력 라벨
    public init?(modelURL: URL)                                 // 모델을 못 읽으면 nil
    public func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?]
    static func cropRect(for face: FaceGeometry, extent: CGRect, margin: Double) -> CGRect
    static func estimate(from observations: [VNClassificationObservation]) -> GenderEstimate? }
RenderTuning.genderCropMargin

// 앱 (Task 3)
AppModel.Policy.bundledGenderModelName, bundledGenderModelExtension
AppModel+Live: bundledGenderEstimator() -> CoreMLGenderEstimator?

// 테스트 (Task 3)
GenderEvaluation { struct Result { accuracy: Double; coverage: Double; perPhoto: [String: (correct: Int, estimated: Int, total: Int)] }
    static func evaluate(estimator:labels:fixtureFolder:tuning:) throws -> Result }
```

---

### Task 1: 후보 모델 조사와 권고 — 사용자 승인 관문

**Files:**
- Create: `docs/research/2026-10-2X-gender-model-candidates.md` (날짜는 실행일)

- [ ] **Step 1: 조사**

웹에서 공개 성별 분류 모델을 찾아 후보 3~5개를 표로 정리한다. 열: 이름 · 출처 URL · 형식(Core ML / ONNX / PyTorch / Caffe) · 파일 크기 · 입력 크기 · 출력 라벨 · 라이선스(원문 한 줄 인용 + 링크) · 학습 데이터셋과 그 라이선스 · 보고된 정확도와 편향(피부톤·나이·성별별 수치가 있으면 그대로, 없으면 "보고 없음") · Core ML 변환 경로(이미 Core ML이면 "변환 불필요", 아니면 coremltools 변환 가능성과 위험) · 비고(마지막 갱신일, 유지 여부). 기억에 의존해 라이선스를 적지 않는다. 확인하지 못한 칸은 "확인 못 함"으로 둔다.

- [ ] **Step 2: 문서 작성**

문서는 저장소 문서 규칙대로 `## 사람이 확인할 것`(후보 표, 권고 1순위와 이유, 상한 30 MB 안인지, 라이선스가 상업 배포를 허용하는지의 **원문 인용**, 위험, 사용자가 고를 것)과 `## 에이전트 참조`(다운로드 명령, 변환 절차 초안, 출력 라벨 → `Gender` 대응 초안, 검증 명령)로 쓴다. 권고는 "라이선스가 명확하게 허용하고, 크기가 작고, 편향 보고가 있는 것"을 우선한다.

- [ ] **Step 3: 커밋 후 멈춤**

```bash
git add docs/research/2026-10-2X-gender-model-candidates.md
git commit -m "docs: 성별 추정 후보 모델 비교와 권고(H4 승인 관문)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

사용자에게 표와 권고를 보여 주고 선택을 기다린다. 선택이 없으면 Task 2를 시작하지 않는다.

---

### Task 2: 모듈 표·스크립트, 모델 번들, CoreMLGenderEstimator

**Files:**
- Modify: `docs/architecture/modules.md`, `scripts/verify-modules.sh`
- Create: `apple/MellowPhoto/Resources/GenderClassifier.mlmodelc/` (또는 `.mlpackage`, Task 1 결정), `apple/MellowPhoto/Resources/GenderClassifier.README.md`
- Create: `apple/Sources/MellowRendering/Infrastructure/CoreMLGenderEstimator.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`, `apple/MellowPhoto.xcodeproj`
- Test: `apple/Tests/MellowRenderingTests/CoreMLGenderEstimatorTests.swift` (새 파일)

- [ ] **Step 1: 실패하는 테스트 작성**

`CoreMLGenderEstimatorTests.swift`:

```swift
import CoreImage
import MellowShared
import Vision
import XCTest

@testable import MellowRendering

final class CoreMLGenderEstimatorTests: XCTestCase {
    /// 앱 리소스의 모델. 테스트 타깃은 패키지라 저장소 경로로 읽는다.
    private static var modelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MellowPhoto/Resources/GenderClassifier.mlmodelc")
    }

    func testCropRectExpandsTheFaceBoxIntoAClampedSquare() {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.1, height: 0.3))
        let crop = CoreMLGenderEstimator.cropRect(for: face, extent: extent, margin: 0.25)
        XCTAssertEqual(crop.width, crop.height, "정사각형")
        XCTAssertGreaterThan(crop.width, 150, "긴 변(150px)에 여백을 더한다")
        XCTAssertTrue(extent.contains(crop), "이미지 안으로 자른다")
        let edge = FaceGeometry(boundingBox: NormalizedRect(x: 0.95, y: 0.9, width: 0.1, height: 0.2))
        XCTAssertTrue(extent.contains(CoreMLGenderEstimator.cropRect(for: edge, extent: extent, margin: 0.25)))
    }

    func testTopLabelMapsToGenderOrNil() {
        func observation(_ identifier: String, _ confidence: Float) -> VNClassificationObservation {
            let observation = VNClassificationObservation()
            observation.setValue(identifier, forKey: "identifier")
            observation.setValue(confidence, forKey: "confidence")
            return observation
        }
        let male = try! XCTUnwrap(CoreMLGenderEstimator.Labels.male.first)
        let female = try! XCTUnwrap(CoreMLGenderEstimator.Labels.female.first)
        XCTAssertEqual(
            CoreMLGenderEstimator.estimate(from: [observation(female, 0.8), observation(male, 0.2)]),
            GenderEstimate(gender: .female, confidence: 0.8))
        XCTAssertNil(CoreMLGenderEstimator.estimate(from: [observation("unknown", 0.9)]))
        XCTAssertNil(CoreMLGenderEstimator.estimate(from: []))
    }

    func testEstimatorReturnsOneEstimatePerFaceInOrder() throws {
        let estimator = try XCTUnwrap(CoreMLGenderEstimator(modelURL: Self.modelURL), "모델 리소스가 있어야 한다")
        let image = try ImageLoader().load(url: try PeopleFixtures.url("couple-01.jpg"), maxDimension: 1200)
        let faces = try VisionFaceAnalyzer().analyze(image)
        let estimates = try estimator.estimate(image, faces: faces)
        XCTAssertEqual(estimates.count, faces.count)
        XCTAssertTrue(estimates.allSatisfy { ($0?.confidence ?? 0) >= 0 && ($0?.confidence ?? 0) <= 1 })
        XCTAssertEqual(try estimator.estimate(image, faces: []), [])
        XCTAssertNil(CoreMLGenderEstimator(modelURL: URL(fileURLWithPath: "/nonexistent.mlmodelc")))
    }
}
```

(`VNClassificationObservation`을 KVC로 만드는 것이 CI Xcode에서 막히면 `estimate(from:)`의 입력을 `[(identifier: String, confidence: Double)]`로 바꾸고 호출부가 observation을 그 튜플로 옮긴다. 테스트도 같은 형태로.)

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter CoreMLGenderEstimatorTests` → 컴파일 실패.

- [ ] **Step 3: 구현**

1. `docs/architecture/modules.md` 의존성 표의 MellowRendering 행 import 허용에 `CoreML`을 더하고 캔버스 규칙에 "`CoreMLGenderEstimator`(Infrastructure, public)는 앱이 모델 URL을 주입, 얼굴 상자 사방 25% 넓힌 정사각형을 `VNCoreMLRequest`로 분류, 라벨 대응은 `Labels` 한 곳" 추가. `scripts/verify-modules.sh`의 MellowRendering 허용 배열에 `CoreML` 추가. `./scripts/verify-modules.sh`가 통과하는지 확인.
2. 모델: Task 1 문서의 절차대로 다운로드(새 빈 폴더) → 필요하면 변환(`python3 -I convert.py <입력> <출력>`, 스크립트는 다른 폴더) → `xcrun coremlcompiler compile <모델>.mlmodel <출력 폴더>`로 `.mlmodelc` → `apple/MellowPhoto/Resources/GenderClassifier.mlmodelc/`로 복사. `du -sh`로 크기 확인(Task 1 상한 이내). `GenderClassifier.README.md`에 출처 URL·버전·라이선스 원문 인용·변환 절차·날짜·출력 라벨을 적는다.
3. `RenderTuning`: `public var genderCropMargin = 0.25`.
4. `CoreMLGenderEstimator.swift`:

```swift
import CoreImage
import CoreML
import MellowShared
import Vision

/// Core ML 성별 분류기. 얼굴 상자를 넓혀 자른 뒤 VNCoreMLRequest로 분류한다. 임계값은 PhotoPipeline이 적용한다.
public struct CoreMLGenderEstimator: GenderEstimator {
    /// 모델 출력 라벨과 Gender의 대응. 모델을 바꾸면 여기만 고친다. (Task 1에서 고른 모델의 라벨로 채운다)
    public enum Labels {
        public static let male: Set<String> = ["male"]
        public static let female: Set<String> = ["female"]
    }

    private let model: VNCoreMLModel
    private let margin: Double

    /// 모델을 못 읽으면 nil. 앱은 그때 추정기 없이 조립한다(모두 미지정).
    public init?(modelURL: URL, tuning: RenderTuning = RenderTuning()) {
        guard let compiled = try? MLModel(contentsOf: modelURL), let model = try? VNCoreMLModel(for: compiled) else {
            return nil
        }
        self.model = model
        margin = tuning.genderCropMargin
    }

    public func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] {
        try faces.map { face in
            let crop = Self.cropRect(for: face, extent: image.extent, margin: margin)
            guard !crop.isEmpty else { return nil }
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            #if targetEnvironment(simulator)
                request.usesCPUOnly = true
            #endif
            try VNImageRequestHandler(ciImage: image.cropped(to: crop), options: [:]).perform([request])
            return Self.estimate(from: request.results as? [VNClassificationObservation] ?? [])
        }
    }

    /// 얼굴 상자를 긴 변 기준 정사각형으로 만들고 사방 margin 비율만큼 넓힌 뒤 이미지 안으로 자른다.
    static func cropRect(for face: FaceGeometry, extent: CGRect, margin: Double) -> CGRect {
        let box = face.boundingBox
        let width = box.width * extent.width
        let height = box.height * extent.height
        let side = max(width, height) * (1 + 2 * margin)
        let center = CGPoint(x: extent.minX + box.midX * extent.width, y: extent.minY + box.midY * extent.height)
        let square = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        return square.intersection(extent)
    }

    /// 가장 높은 분류가 남·여 라벨이면 그 추정, 아니면 nil.
    static func estimate(from observations: [VNClassificationObservation]) -> GenderEstimate? {
        guard let top = observations.max(by: { $0.confidence < $1.confidence }) else { return nil }
        if Labels.male.contains(top.identifier) {
            return GenderEstimate(gender: .male, confidence: Double(top.confidence))
        }
        if Labels.female.contains(top.identifier) {
            return GenderEstimate(gender: .female, confidence: Double(top.confidence))
        }
        return nil
    }
}
```

교차 부분이 비면(얼굴이 사진 밖) nil. `cropRect`는 정사각형을 이미지와 교차하므로 가장자리에서 정사각형이 아닐 수 있다 — 테스트의 "정사각형" 단언은 가운데 얼굴에만 둔다(위 테스트가 그렇다).

5. `cd apple && xcodegen generate --quiet`(리소스 폴더 추가).

- [ ] **Step 4: 통과 확인**

Run: `./scripts/verify-modules.sh` 통과(CoreML 허용 반영). `cd apple && swift test` → Rendering 268(+3), 0 failures. Mac 앱 빌드·테스트 → 85, `TEST SUCCEEDED`. lint 출력 없음. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add docs/architecture/modules.md scripts/verify-modules.sh apple/MellowPhoto/Resources/GenderClassifier.mlmodelc apple/MellowPhoto/Resources/GenderClassifier.README.md apple/Sources/MellowRendering/Infrastructure/CoreMLGenderEstimator.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/MellowPhoto.xcodeproj apple/Tests/MellowRenderingTests/CoreMLGenderEstimatorTests.swift
git commit -m "feat(rendering): Core ML 성별 추정기와 모델 번들, 모듈 표에 CoreML 허용

<모델 이름·버전·크기·라이선스 한 줄>. 얼굴 상자 사방 25% 넓힌 정사각형을 분류.
임계값·수동 우선 규칙은 H2 그대로.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 라벨 정확도 측정과 앱 주입

**Files:**
- Modify: `apple/MellowPhoto/Platform/AppModel+Live.swift`, `apple/MellowPhoto/Application/AppModel.swift` (`Policy` 상수)
- Create: `apple/Tests/MellowRenderingTests/GenderEvaluationTests.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`GenderEvaluationTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 생성 사진 라벨 대비 정확도. 수치는 기록용이고 관문이 아니다(VALIDATION에 적고 사용자가 판단한다).
enum GenderEvaluation {
    struct PhotoResult: Equatable {
        var correct = 0
        var estimated = 0
        var total = 0
    }

    struct Result {
        var perPhoto: [String: PhotoResult]
        var accuracy: Double { let c = perPhoto.values.map(\.correct).reduce(0, +); let e = perPhoto.values.map(\.estimated).reduce(0, +); return e == 0 ? 0 : Double(c) / Double(e) }
        var coverage: Double { let e = perPhoto.values.map(\.estimated).reduce(0, +); let t = perPhoto.values.map(\.total).reduce(0, +); return t == 0 ? 0 : Double(e) / Double(t) }
    }

    /// 라벨의 모든 사진(저장소 원본 폴더)에서 Vision 얼굴 수가 라벨 인원과 같은 사진만 센다. ambiguous 사람은 뺀다.
    static func evaluate(estimator: any GenderEstimator, labels: PeopleLabels, fixtureFolder: URL, tuning: RenderTuning) throws -> Result {
        var perPhoto: [String: PhotoResult] = [:]
        for photo in labels.photos {
            let image = try ImageLoader().load(url: fixtureFolder.appendingPathComponent(photo.file), maxDimension: 1200)
            let faces = try VisionFaceAnalyzer().analyze(image)
            guard faces.count == photo.people.count else { continue }
            let estimates = PhotoPipeline.acceptedEstimates(try estimator.estimate(image, faces: faces), faces: faces, tuning: tuning)
            var result = PhotoResult()
            for (estimate, person) in zip(estimates, photo.people) where !person.ambiguous {
                result.total += 1
                guard let estimate else { continue }
                result.estimated += 1
                if estimate.gender.rawValue == person.gender {
                    result.correct += 1
                }
            }
            perPhoto[photo.file] = result
        }
        return Result(perPhoto: perPhoto)
    }
}

final class GenderEvaluationTests: XCTestCase {
    private static var modelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MellowPhoto/Resources/GenderClassifier.mlmodelc")
    }

    func testAccuracyAgainstLabelsIsMeasuredAndReported() throws {
        let estimator = try XCTUnwrap(CoreMLGenderEstimator(modelURL: Self.modelURL))
        let labels = try JSONDecoder().decode(
            PeopleLabels.self, from: Data(contentsOf: PeopleFixtures.sharedFolder.appendingPathComponent("labels.json")))
        let result = try GenderEvaluation.evaluate(
            estimator: estimator, labels: labels, fixtureFolder: PeopleFixtures.sharedFolder, tuning: RenderTuning())
        XCTAssertFalse(result.perPhoto.isEmpty, "적어도 한 사진은 Vision 얼굴 수가 라벨과 같아야 한다")
        for (file, photo) in result.perPhoto.sorted(by: { $0.key < $1.key }) {
            // VALIDATION에 옮겨 적는 수치. 관문이 아니다.
            print("gender-evaluation \(file): correct \(photo.correct) / estimated \(photo.estimated) / total \(photo.total)")
        }
        print("gender-evaluation accuracy \(result.accuracy) coverage \(result.coverage)")
        XCTAssertGreaterThanOrEqual(result.accuracy, 0)
        XCTAssertLessThanOrEqual(result.accuracy, 1)
        // 수동 지정은 추정과 무관하게 남는다(H2 규칙 재확인).
        var recipe = EditRecipe()
        let image = try ImageLoader().load(url: try PeopleFixtures.url("couple-01.jpg"), maxDimension: 1200)
        let faces = try VisionFaceAnalyzer().analyze(image)
        let estimates = PhotoPipeline.acceptedEstimates(try estimator.estimate(image, faces: faces), faces: faces, tuning: RenderTuning())
        recipe.people.individuals = [PersonRecord(anchor: PersonAnchor(faceBox: faces[0].boundingBox), gender: .male)]
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, genderEstimates: estimates),
            tuning: RenderTuning())
        XCTAssertEqual(context.faceTargets[0].gender, .male)
    }
}
```

`AppModelTests.swift` 끝에 추가:

```swift
    func testMissingModelMakesNoEstimatorAndEveryoneStaysUnassigned() async throws {
        XCTAssertNil(CoreMLGenderEstimator(modelURL: root.appendingPathComponent("missing.mlmodelc")))
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.personChips.map(\.source), [.none, .none])
        XCTAssertEqual(AppModel.Policy.bundledGenderModelName, "GenderClassifier")
        XCTAssertNotNil(Bundle.main.url(forResource: AppModel.Policy.bundledGenderModelName, withExtension: AppModel.Policy.bundledGenderModelExtension) ?? Bundle(for: AppModel.self).url(forResource: AppModel.Policy.bundledGenderModelName, withExtension: AppModel.Policy.bundledGenderModelExtension), "앱 번들에 모델이 있다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter GenderEvaluationTests` → 컴파일 실패(없는 타입). Mac 앱 테스트 → `Policy.bundledGenderModelName` 없음.

- [ ] **Step 3: 구현**

`AppModel.Policy`: `static let bundledGenderModelName = "GenderClassifier"`, `static let bundledGenderModelExtension = "mlmodelc"`. `AppModel+Live.swift`: `bundledGenderEstimator()`가 번들 URL을 찾아 `CoreMLGenderEstimator(modelURL:tuning:)`를 만들고(없으면 nil, 안내 문구 없음 — 추정은 보조 기능), `PhotoPipeline(..., genderEstimator: bundledGenderEstimator(), ...)`로 주입.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering 269(+1), 0 failures. Mac 앱 테스트 → 86. lint 출력 없음. 출력에서 `gender-evaluation` 줄을 모아 둔다(Task 4 VALIDATION).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Platform/AppModel+Live.swift apple/MellowPhoto/Application/AppModel.swift apple/Tests/MellowRenderingTests/GenderEvaluationTests.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 번들 성별 추정기를 주입하고 생성 사진 라벨로 정확도 측정

모델이 없으면 추정 없이 동작(모두 미지정). 정확도는 기록용이며 관문이 아니다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: VALIDATION·스토어·개인정보 검토 항목

**Files:**
- Modify: `VALIDATION.md`, `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md`

- [ ] **Step 1: 전체 검증**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh` → 종료 코드 0(로컬은 iOS 시뮬레이터를 건너뛴다. `MELLOW_IOS_TESTS` 금지. iOS는 CI에서 확인, 사용자 조치).

- [ ] **Step 2: VALIDATION**

H 절 아래에 `### H4 성별 자동 추정 (2026-10-XX)` 소절: 고른 모델(이름·버전·크기·라이선스 원문 링크·앱 크기 증가량), 자동 검증(명령·테스트 수), 정확도 표(사진별 correct/estimated/total, 전체 accuracy·coverage, 피부톤·나이대·자세·안경·가림별로 라벨을 기준으로 다시 묶은 표 — 생성 사진 20명 남짓이라 통계적 의미가 작다고 명시), 임계값(0.75·5%·0.6rad), 스펙과 다르게 한 것, 미검증(실사진 정확도·편향, 실기기 추론 시간, 모델이 큰 기기에서의 메모리), 사용자 조치(앱 설명·심사 노트 문구 결정, 라이선스 최종 확인). 수행하지 않은 검증을 통과로 쓰지 않는다. 배포는 하지 않았다고 적는다.

스펙: 결정 표의 자동 추정 행에 "(H4 수행) 고른 모델 …"을 덧붙이고 1.1 표의 H4 행을 실제 파일 이름으로 고친다.

- [ ] **Step 3: 커밋**

```bash
git add VALIDATION.md docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md
git commit -m "docs: H4 성별 자동 추정 검증 기록과 정확도 표

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** 결정 표 "자동 추정 모델은 H4로" → Task 1 관문·Task 2 구현. §1.1 H4 행(모듈 표 CoreML + `verify-modules.sh` 같은 커밋) → Task 2. §1.5(포트·임계값·수동 우선) → Task 2·3이 H2 규칙을 그대로 쓰고 테스트로 재확인. §3 정확도 측정 식(맞은 수 / 추정 낸 수, 추정 비율, 모호한 사람 제외, Vision 불일치 사진 제외) → Task 3 `GenderEvaluation`. §4 VALIDATION 정확도 표 → Task 4. §5 H4 행과 같다.
- **타입 일관성:** `CoreMLGenderEstimator(modelURL:tuning:)`·`Labels`·`cropRect`·`estimate(from:)`, `RenderTuning.genderCropMargin`, `AppModel.Policy.bundledGenderModelName`·`bundledGenderModelExtension`, `bundledGenderEstimator()`, `GenderEvaluation.evaluate`·`Result`·`PhotoResult`, `PeopleFixtures`(H3)를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 406 → 409(T2) → 410(T3), 앱 Mac 85 → 86(T3). (목표 줄의 409는 T2 기준이며 T3 뒤 410이다.)
- **Review Focus 매핑:** 1→Task 3, 2→Task 2(+H2), 3→Task 3, 4→Task 3. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** 모델 이름·라벨·라이선스는 Task 1 결과로 정해지는 값이며 "Task 1에서 채운다"고 명시했다. `Labels`의 초기값 `"male"`·`"female"`은 모델 라벨로 바꿔야 한다는 주석이 있다. 그 밖에 "TBD/TODO/나중에" 없음.
