import Foundation
import MellowLibrary
import MellowShared

/// 구 Mac 앱의 presets.json을 한 번만 세션으로 흡수한다.
enum LegacyMacPresets {
    /// Application Support 아래 구 Mac 앱의 프리셋 파일 위치.
    static let relativePath = "MellowPhoto/presets.json"
    /// 흡수를 마친 파일에 붙이는 확장자. 다음 실행에서 다시 읽지 않는다.
    static let importedExtension = "imported"

    /// 구 앱은 여섯 값을 모두 기록했다. 빠진 값은 현재 기본값으로 채운다.
    private struct LegacyPreset: Decodable {
        struct Adjustments: Decodable {
            var exposure: Double?
            var contrast: Double?
            var saturation: Double?
            var warmth: Double?
            var skin: Double?
            var faceSlim: Double?
        }

        var name: String
        var adjustments: Adjustments

        var values: PresetValues {
            let color = ColorAdjustments()
            let portrait = PortraitAdjustments()
            return PresetValues(
                color: ColorAdjustments(
                    exposure: adjustments.exposure ?? color.exposure,
                    contrast: adjustments.contrast ?? color.contrast,
                    saturation: adjustments.saturation ?? color.saturation,
                    warmth: adjustments.warmth ?? color.warmth),
                portrait: PortraitAdjustments(
                    skinSmoothing: adjustments.skin ?? portrait.skinSmoothing,
                    faceSlim: adjustments.faceSlim ?? portrait.faceSlim))
        }
    }

    @MainActor
    static func importIfPresent(into session: ProjectSession, applicationSupport: URL) {
        let file = applicationSupport.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        // 읽지 못한 파일은 그대로 둔다. 다음 버전이 다시 시도할 수 있고 사용자 데이터도 보존된다.
        guard let data = try? Data(contentsOf: file) else { return }
        guard let presets = try? JSONDecoder().decode([LegacyPreset].self, from: data) else { return }
        for preset in presets {
            session.addPreset(named: preset.name, values: preset.values)
        }
        markImported(file)
    }

    /// 흡수한 파일을 옆에 보관한다. 지난 흡수본이 있으면 지우지 않고 겹치지 않는 이름을 쓴다.
    private static func markImported(_ file: URL) {
        let imported = file.appendingPathExtension(importedExtension)
        let target =
            FileManager.default.fileExists(atPath: imported.path)
            ? file.appendingPathExtension(UUID().uuidString).appendingPathExtension(importedExtension)
            : imported
        try? FileManager.default.moveItem(at: file, to: target)
    }
}
