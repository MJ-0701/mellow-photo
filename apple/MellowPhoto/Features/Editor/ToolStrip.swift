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
                ForEach([EditorTool.crop, .adjust, .beauty, .makeup, .body, .background, .retouch, .warp]) {
                    toolButton($0)
                }
            }
            .padding(.horizontal, 8)
            #if os(macOS)
                // 좁은 인스펙터에서는 도구가 다 보이지 않는다. 마우스로도 끝까지 갈 수 있게 스크롤 막대를 둔다.
                .padding(.bottom, Theme.toolStripScrollerInset)
            #endif
        }
        #if os(macOS)
            .scrollIndicators(.visible)
        #else
            .scrollIndicators(.hidden)
        #endif
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
