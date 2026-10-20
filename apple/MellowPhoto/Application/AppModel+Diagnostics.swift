import CoreGraphics
import Foundation
import MellowShared

/// 레시피를 JSON으로 펼쳐 기본 레시피와 다른 잎만 "경로=값"으로 적는다.
/// 키 경로는 영어 식별자(모듈 값 이름 그대로).
/// 수동 편집(`operations`)은 점·획마다 잎이 여러 개라 개수 한 줄(`operations=N`)로 줄인다.
enum RecipeSummary {
    /// 레시피 JSON의 수동 편집 배열 키.
    static let operationsKey = "operations"

    static func nonDefaultLines(_ recipe: EditRecipe) -> [String] {
        let current = leaves(of: recipe)
        let defaults = leaves(of: EditRecipe())
        var lines = current.filter { defaults[$0.key] != $0.value }.map { "\($0.key)=\($0.value)" }
        if !recipe.operations.isEmpty {
            lines.append("\(operationsKey)=\(recipe.operations.count)")
        }
        return lines.sorted()
    }

    private static func leaves(of recipe: EditRecipe) -> [String: String] {
        guard let data = try? JSONEncoder().encode(recipe),
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        object["schemaVersion"] = nil
        object[operationsKey] = nil
        var result: [String: String] = [:]
        flatten(object, path: "", into: &result)
        return result
    }

    private static func flatten(_ value: Any, path: String, into result: inout [String: String]) {
        switch value {
        case let dictionary as [String: Any]:
            for (key, child) in dictionary {
                flatten(child, path: path.isEmpty ? key : "\(path).\(key)", into: &result)
            }
        case let array as [Any]:
            for (index, child) in array.enumerated() {
                flatten(child, path: "\(path)[\(index)]", into: &result)
            }
        case let number as NSNumber:
            result[path] = text(of: number)
        case let string as String:
            result[path] = string
        default:
            result[path] = "null"
        }
    }

    /// JSON의 참·거짓도 NSNumber로 온다.
    /// 형식 ID로 구분해 true/false로 적고 나머지 수는 소수 둘째 자리까지 적는다.
    private static func text(of number: NSNumber) -> String {
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return String(format: "%.2f", number.doubleValue) }
        return number.boolValue ? "true" : "false"
    }
}

/// 기기 모델 식별자(스펙 G4 6).
/// iOS 기기는 uname의 machine(예: iPhone16,2)이다.
/// 시뮬레이터는 machine이 CPU 이름이라 SIMULATOR_MODEL_IDENTIFIER를 먼저 본다.
/// macOS는 sysctl hw.model(예: Mac14,2)이다.
enum DeviceModel {
    /// 식별자를 읽지 못했을 때.
    /// 진단의 앱 버전·빌드를 읽지 못했을 때도 쓴다.
    static let unknown = "?"

    static var identifier: String {
        #if os(macOS)
            return systemControl("hw.model") ?? unknown
        #else
            if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return simulated
            }
            var info = utsname()
            guard uname(&info) == 0 else { return unknown }
            let machine = withUnsafeBytes(of: &info.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return machine.isEmpty ? unknown : machine
        #endif
    }

    #if os(macOS)
        /// sysctl 문자열 값.
        /// 크기를 먼저 묻고 그만큼 읽는다.
        private static func systemControl(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
            let value = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            return value.isEmpty ? nil : value
        }
    #endif
}

extension AppModel {
    enum DiagnosticItem {
        case build, device, photo, preview, analysis, failure
    }

    /// 정보 시트 "진단".
    /// 스크린샷 한 장으로 전제 조건(얼굴·사람·관절)과 적용 중인 값을 볼 수 있다.
    var diagnosticLines: [String] {
        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        let version = bundleInfo["CFBundleShortVersionString"] as? String ?? DeviceModel.unknown
        let build = bundleInfo["CFBundleVersion"] as? String ?? DeviceModel.unknown
        var lines = [
            "\(UserMessage.diagnosticLabel(.build)) \(version) (\(build))",
            "\(UserMessage.diagnosticLabel(.device)) \(DeviceModel.identifier) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
        ]
        if let info = selectedInfo {
            let width = Int(info.pixelSize.width)
            let height = Int(info.pixelSize.height)
            lines.append("\(UserMessage.diagnosticLabel(.photo)) \(width)×\(height)")
            lines.append(
                "\(UserMessage.diagnosticLabel(.analysis)) faces=\(info.faces.count) person=\(info.hasPerson) body=\(info.hasBody)"
            )
        }
        if let preview {
            lines.append("\(UserMessage.diagnosticLabel(.preview)) preview=\(preview.width)×\(preview.height)")
        }
        lines += RecipeSummary.nonDefaultLines(currentRecipe)
        if let lastRenderFailure {
            lines.append("\(UserMessage.diagnosticLabel(.failure)) \(lastRenderFailure)")
        }
        return lines
    }
}
