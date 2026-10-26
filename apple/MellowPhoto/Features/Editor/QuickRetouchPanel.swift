import SwiftUI

/// 기존 보정 기능의 목적별 진입점.
/// 카드 설명과 비활성 사유는 좁은 패널에서도 세로로 늘어나며 스크롤로 접근한다.
struct QuickRetouchPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(UserMessage.splitCompare) { model.toggleSplitCompare() }
                    .accessibilityIdentifier("quick.compare")
                Spacer()
                Button("한 단계 되돌리기") { model.undo() }
                    .disabled(!model.canUndo)
                    .accessibilityIdentifier("quick.undo")
            }
            .font(.caption)
            ForEach(QuickRetouchAction.allCases) { action in
                let reason = model.quickUnavailableReason(action)
                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        Task { await model.applyQuickAction(action) }
                    } label: {
                        Text(action.title).font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .disabled(reason != nil)
                    .accessibilityIdentifier("quick.\(action.rawValue)")
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("강도 조절") {
                        switch action {
                        case .automatic, .brighten: model.selectTool(.adjust)
                        case .portrait: model.selectTool(.beauty)
                        case .background: model.selectTool(.background)
                        case .night: model.selectTool(.look)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("quick.details.\(action.rawValue)")
                    if let reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            Button {
                Task { await model.autoEnhanceAll() }
            } label: {
                Label(UserMessage.quickBatch, systemImage: "photo.stack")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Theme.canvas)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.session.photos.count < 2)
            .accessibilityIdentifier("quick.batch")
            Text(UserMessage.quickBatchDetail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.session.photos.count < 2 {
                Text(UserMessage.quickBatchNeedsPhotos).font(.caption).foregroundStyle(.secondary)
            }
            if let report = model.quickRetouchProgress, !model.isQuickRetouching {
                Text(UserMessage.quickSummary(report)).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("quick.summary")
            }
        }
    }
}
