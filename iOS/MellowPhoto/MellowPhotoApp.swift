import SwiftUI

@main struct MellowPhotoApp: App {
    @StateObject private var store = MobileStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            MobileEditor(store: store)
                .preferredColorScheme(.dark)
                .task { await store.restore() }
                .onChange(of: phase) { _, phase in
                    if phase != .active {
                        store.persist()
                        // Finish the current image; stop a batch when the app leaves the foreground.
                        if phase == .background { store.cancelExport = true }
                    }
                }
        }
    }
}
