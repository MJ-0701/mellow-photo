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
                Button("−") { zoom = Theme.clampedZoom(zoom - Theme.zoomStep) }
                Text(zoom == Theme.zoomRange.lowerBound ? "화면에 맞춤" : "\(Int(zoom * 100))%").font(.caption2)
                    .frame(width: 75)
                Button("+") { zoom = Theme.clampedZoom(zoom + Theme.zoomStep) }
            }
            Button {
                model.toggleSplitCompare()
            } label: {
                Text(model.compareMode == .split ? UserMessage.splitCompareDone : UserMessage.splitCompare)
                    .font(.caption.weight(.medium))
                    .frame(minWidth: 44, minHeight: 40)
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
