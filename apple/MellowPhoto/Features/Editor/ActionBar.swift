import SwiftUI

struct ActionBar: View {
    @Environment(AppModel.self) private var model
    @Binding var zoom: Double
    var showsZoom = false

    var body: some View {
        HStack {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40)
            }
            .disabled(!model.canUndo).accessibilityLabel("실행 취소").help("실행 취소 ⌘Z")
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 40)
            }
            .disabled(!model.canRedo).accessibilityLabel("다시 실행").help("다시 실행 ⇧⌘Z")
            Spacer()
            if let size = model.selectedInfo?.pixelSize {
                Text("\(Int(size.width)) × \(Int(size.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if showsZoom {
                Button("−") { zoom = max(1, zoom - 0.5) }
                Text(zoom == 1 ? "화면에 맞춤" : "\(Int(zoom * 100))%").font(.caption2).frame(width: 75)
                Button("+") { zoom = min(4, zoom + 0.5) }
            }
            Button {
                model.isComparing.toggle()
            } label: {
                Text(model.isComparing ? "보정본" : "원본 비교")
                    .font(.caption.weight(.medium))
                    .frame(minWidth: 65, minHeight: 40)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .disabled(model.isBusy || !model.isReady)
    }
}
