import SwiftUI

struct RetouchDirectoryPanel: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("사진의 피부·눈·입·턱밑·몸을 누르면 사람과 조절 항목을 찾아요. 클릭만으로 보정값은 바뀌지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
            if let reason = model.regionSelectionUnavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            TargetChips()
            if model.focusedRetouchDestination == .sideChest {
                Text("부유방을 조절할 사람을 선택하세요. 연결된 몸이나 옆선이 없으면 조절할 수 없어요.")
                    .font(.caption)
                ForEach(model.faces.indices, id: \.self) { index in
                    Button("사람 \(index + 1) 부유방 조절") { model.chooseRetouchPerson(index) }
                        .accessibilityIdentifier("retouch.person.\(index)")
                }
            }
            TextField("보정 도구 찾기", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("retouch.search")
            ForEach(RetouchDestination.all.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) })
            { destination in
                Button(destination.title) { model.openRetouchDestination(destination) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("부유방은 여성 그룹이나 사람을 골라 조절해요. 수동 브러시가 있으면 얼굴형·체형은 잠겨요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
