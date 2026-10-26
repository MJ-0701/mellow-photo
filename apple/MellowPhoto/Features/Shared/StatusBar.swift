import SwiftUI

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if model.isExporting { ProgressView(value: model.exportProgress) }
            if model.isQuickRetouching, let report = model.quickRetouchProgress {
                ProgressView(value: Double(report.processed), total: Double(report.total))
                    .accessibilityIdentifier("quick.progress")
            }
            HStack {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.isExporting {
                    Button("나머지 취소") { model.cancelExport() }.font(.caption)
                }
                if model.isQuickRetouching {
                    Button(UserMessage.quickCancel) { model.cancelQuickRetouch() }
                        .font(.caption)
                        .disabled(model.quickRetouchCancellationRequested)
                        .accessibilityIdentifier("quick.cancel")
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}
