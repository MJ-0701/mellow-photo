import SwiftUI

@main
struct MellowPhotoApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EditorScene()
                .environment(model)
                .preferredColorScheme(.dark)
                #if os(macOS)
                    .frame(minWidth: 1040, minHeight: 700)
                #endif
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in
                    // 현재 사진은 마무리하고, 백그라운드에서는 일괄 저장과 미리보기 작업을 멈춘다.
                    if phase == .background {
                        model.cancelExport()
                        model.stopWork()
                    }
                    if phase == .active {
                        model.resumeWork()
                        // 불러오다 멈춘 선택은 다시 불러온다. 읽기에 실패한 선택은 복구 화면에 맡겨 알림을 되풀이하지 않는다.
                        if !model.isReady, model.selectionFailure == nil, let id = model.session.selectedPhotoID {
                            model.select(id)
                        }
                    }
                }
        }
        #if os(macOS)
            .defaultSize(width: 1320, height: 860)
        #endif
        .commands {
            CommandGroup(replacing: .undoRedo) {
                // 텍스트 입력 중에는 꺼서 ⌘Z가 사진 편집 대신 입력란의 실행 취소로 가게 한다.
                Button("실행 취소") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo || model.isTextEntryActive)
                Button("다시 실행") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo || model.isTextEntryActive)
            }
        }
    }
}
