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
                    if action == .portrait {
                        OneTouchRow(fixedTarget: .all, buttonIdentifier: "quick.portrait")
                            .disabled(reason != nil)
                        if !model.currentRecipe.people.individuals.isEmpty {
                            Text("개인별 수동 설정은 전체 원터치보다 우선해요. 아래에서 사람을 골라 그 사람의 원터치를 적용할 수 있어요.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("사람별 원터치 조절") { model.selectTool(.beauty) }
                                .font(.caption)
                        }
                    } else {
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
                    }
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
            Button("부위를 눌러 보정 도구 찾기") { model.selectTool(.region) }
                .accessibilityIdentifier("quick.region")
            Button("이중턱 조절") { model.openRetouchDestination(.doubleChin) }
                .accessibilityIdentifier("quick.doubleChin")
            Button("부유방 조절") { model.openRetouchDestination(.sideChest) }
                .accessibilityIdentifier("quick.sideChest")
            Button("모든 보정 도구 찾기") { model.selectTool(.region) }
            Text("이중턱·체형은 인물 원터치에 포함되지 않아요. 부위를 고른 뒤 직접 강도를 조절해요.")
                .font(.caption).foregroundStyle(.secondary)
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
