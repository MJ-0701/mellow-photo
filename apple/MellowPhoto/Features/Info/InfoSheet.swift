import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Mellow Photo") {
                    Text("사진과 얼굴 분석은 기기 내부에서 처리합니다. 작업 기록은 앱에 저장되고, 사진 앱·파일 원본은 변경하지 않습니다.")
                    Text("앱 삭제 시 내부 작업 기록은 사라집니다. 완성한 사진은 저장해 주세요.")
                }
                Section("도움말") {
                    Link("지원 페이지", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/")!)
                    Link(
                        "개인정보 안내",
                        destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/privacy.html")!)
                    Link("이메일 문의", destination: URL(string: "mailto:jack2718@naver.com")!)
                }
                diagnostics
            }
            .navigationTitle("도움말과 개인정보")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    /// 기기 확인 때 스크린샷 한 장이나 복사로 전제 조건과 적용 값을 전한다.
    private var diagnostics: some View {
        let lines = model.diagnosticLines
        return Section(UserMessage.diagnosticsTitle) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption.monospaced()).textSelection(.enabled)
            }
            Button(UserMessage.copyDiagnostics) { copy(lines.joined(separator: "\n")) }
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}
