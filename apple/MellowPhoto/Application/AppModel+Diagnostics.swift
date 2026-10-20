import CoreGraphics
import Foundation
import MellowShared

/// 레시피를 JSON으로 펼쳐 기본 레시피와 다른 잎만 "경로=값"으로 적는다. 키 경로는 영어 식별자(모듈 값 이름 그대로).
enum RecipeSummary {
    static func nonDefaultLines(_ recipe: EditRecipe) -> [String] {
        let current = leaves(of: recipe)
        let defaults = leaves(of: EditRecipe())
        return current.filter { defaults[$0.key] != $0.value }.map { "\($0.key)=\($0.value)" }.sorted()
    }

    private static func leaves(of recipe: EditRecipe) -> [String: String] {
        guard let data = try? JSONEncoder().encode(recipe),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return [:] }
        var result: [String: String] = [:]
        flatten(object, path: "", into: &result)
        result["schemaVersion"] = nil
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

    /// JSON의 참·거짓도 NSNumber로 온다. 형식 ID로 구분해 true/false로 적고 나머지 수는 소수 둘째 자리까지 적는다.
    private static func text(of number: NSNumber) -> String {
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return String(format: "%.2f", number.doubleValue) }
        return number.boolValue ? "true" : "false"
    }
}

extension AppModel {
    enum DiagnosticItem {
        case build, device, photo, preview, analysis, failure
    }

    /// 정보 시트 "진단". 스크린샷 한 장으로 전제 조건(얼굴·사람·관절)과 적용 중인 값을 볼 수 있다.
    var diagnosticLines: [String] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines = [
            "\(UserMessage.diagnosticLabel(.build)) \(version) (\(build))",
            "\(UserMessage.diagnosticLabel(.device)) \(ProcessInfo.processInfo.operatingSystemVersionString)",
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
