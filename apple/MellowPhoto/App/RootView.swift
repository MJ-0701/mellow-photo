import MellowShared
import SwiftUI

/// Task 11이 EditorScene으로 교체한다.
struct RootView: View {
    var body: some View {
        Text("Mellow Photo · \(BuiltInPresets.all.count)개 프리셋")
            .padding()
    }
}
