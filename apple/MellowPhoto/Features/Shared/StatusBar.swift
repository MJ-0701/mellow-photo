import SwiftUI

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if model.isExporting { ProgressView(value: model.exportProgress) }
            HStack {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.isExporting {
                    Button("나머지 취소") { model.cancelExport() }.font(.caption)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}
