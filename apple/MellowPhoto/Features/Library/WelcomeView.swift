import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.macro").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text("좋아하는 순간을,\n조금 더 부드럽게.").font(.largeTitle.weight(.light)).multilineTextAlignment(.center)
            Text("인물 사진을 나답게 다듬어보세요.").font(.subheadline).foregroundStyle(.secondary)
            PhotoPickerButton(prominent: true).buttonStyle(.borderedProminent).controlSize(.large)
            Text("사진은 기기 안에서 처리해요.\n편집 기록 자동 저장")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if model.isRestoring || model.isImporting { ProgressView() }
            Spacer()
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
