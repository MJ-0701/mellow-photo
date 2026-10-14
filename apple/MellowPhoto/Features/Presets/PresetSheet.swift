import SwiftUI

struct PresetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("분위기 이름", text: $name)
                Text("색감·피부·얼굴 슬라이더 값만 저장합니다. 잡티 위치와 수동 변형은 포함하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("분위기 저장")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        model.savePreset(named: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .frame(minWidth: 360, minHeight: 200)
        .onAppear { model.isTextEntryActive = true }
        .onDisappear { model.isTextEntryActive = false }
    }
}
