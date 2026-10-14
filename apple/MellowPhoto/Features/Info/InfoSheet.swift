import SwiftUI

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mellow Photo") {
                    Text("사진과 얼굴 분석은 기기 내부에서 처리합니다. 작업 기록은 앱에 저장되고, 사진 앱·파일 원본은 변경하지 않습니다.")
                    Text("앱 삭제 시 내부 작업 기록은 사라집니다. 완성한 사진은 저장해 주세요.")
                }
                Section("도움말") {
                    Link("지원 페이지", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/")!)
                    Link(
                        "개인정보 안내",
                        destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/privacy.html")!)
                    Link("이메일 문의", destination: URL(string: "mailto:jack2718@naver.com")!)
                }
            }
            .navigationTitle("도움말과 개인정보")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
