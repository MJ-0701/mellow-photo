import MellowEditing
import SwiftUI

/// "전체 사진에 적용"이 복사할 항목을 고르는 톱니 메뉴. 항목마다 켜고 끄는 토글이다.
struct SyncMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(SyncCategory.allCases) { category in
                Toggle(
                    UserMessage.syncCategoryTitle(category),
                    isOn: Binding(
                        get: { model.syncCategories.contains(category) },
                        set: { model.setSyncCategory(category, enabled: $0) }))
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.button)
        .accessibilityLabel(UserMessage.syncMenuLabel)
    }
}
