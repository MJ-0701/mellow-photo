import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: StudioStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = store else { return .terminateNow }
        if store.exporting || store.hasEdits {
            let alert = NSAlert()
            alert.messageText = store.exporting ? "사진을 저장하고 있습니다" : "Mellow Photo를 종료할까요?"
            alert.informativeText = "내보낸 사진과 저장한 프리셋은 유지됩니다. 현재 편집 기록은 앱을 종료하면 사라집니다."
            alert.addButton(withTitle: "계속 편집")
            alert.addButton(withTitle: "종료")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct MellowPhotoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = StudioStore()
    var body: some Scene {
        WindowGroup {
            StudioView(store: store)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(.dark)
                .onAppear { delegate.store = store }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("사진 가져오기…") { store.choosePhotos() }.keyboardShortcut("o")
                Button("현재 사진 내보내기…") { store.export(all: false) }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.selected == nil || store.exporting)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소") { store.undo() }.keyboardShortcut("z").disabled(!store.canUndo)
                Button("다시 실행") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
            }
        }
    }
}
