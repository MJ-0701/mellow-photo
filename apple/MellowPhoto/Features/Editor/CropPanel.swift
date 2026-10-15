import MellowShared
import SwiftUI

/// 비율 버튼, 90° 회전·좌우 반전·되돌리기, 수평 슬라이더.
struct CropPanel: View {
    @Environment(AppModel.self) private var model

    private static let aspectTitles: [CropAspect: String] = [
        .original: "원본", .square: "1:1", .fourFive: "4:5", .threeFour: "3:4", .nineSixteen: "9:16",
    ]

    var body: some View {
        let geometry = model.currentRecipe.geometry
        ScrollView(.horizontal) {
            HStack {
                ForEach(CropAspect.allCases) { aspect in
                    Button(Self.aspectTitles[aspect] ?? "") { model.setCropAspect(aspect) }
                        .tint(model.cropAspect == aspect ? Theme.accent : .secondary)
                        .accessibilityAddTraits(model.cropAspect == aspect ? .isSelected : [])
                }
            }
            .buttonStyle(.bordered).font(.caption)
        }
        .scrollIndicators(.hidden)
        HStack(spacing: 16) {
            Button {
                model.turnClockwise()
            } label: {
                Label("90° 회전", systemImage: "rotate.right")
            }
            Button {
                model.edit(.flipHorizontal(!geometry.flipHorizontal))
            } label: {
                Label("좌우 반전", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Spacer()
            Button("되돌리기") { model.resetGeometry() }.disabled(geometry.isIdentity)
        }
        .buttonStyle(.bordered).font(.caption)
        AdjustmentSlider(
            title: "수평", value: geometry.straightenDegrees,
            range: -GeometryAdjustments.maxStraightenDegrees...GeometryAdjustments.maxStraightenDegrees
        ) { .straightenDegrees($0) }
        Text("사각형의 모서리를 끌어 자를 부분을 정해요. 잡티·변형 위치는 원본 기준으로 그대로 남아요.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
