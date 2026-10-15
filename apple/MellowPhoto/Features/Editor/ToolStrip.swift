import SwiftUI

/// 가로 스크롤 도구 줄. '자동'은 도구가 아니라 즉시 적용 버튼이다.
struct ToolStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                toolButton(.look)
                Button {
                    Task { await model.autoEnhance() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars").font(.title3)
                        Text(UserMessage.toolAuto).font(.caption2)
                    }
                    .frame(width: Theme.toolButtonSize.width, height: Theme.toolButtonSize.height)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("자동 보정")
                ForEach([EditorTool.crop, .adjust, .portrait, .retouch, .warp]) { toolButton($0) }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.selectTool(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol).font(.title3)
                Text(tool.title).font(.caption2)
            }
            .frame(width: Theme.toolButtonSize.width, height: Theme.toolButtonSize.height)
            .background(selected ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
