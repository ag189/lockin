import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.active != nil {
                RunningHeader()
                Divider()
            }

            switch model.screen {
            case .output(_, _, let label):
                OutputView(label: label)
            case .main:
                ScrollView {
                    IdleView()
                        .padding(16)
                }
                .frame(maxHeight: 440)
            }

            Divider()
            FooterView()
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
