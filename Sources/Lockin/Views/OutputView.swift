import SwiftUI

struct OutputView: View {
    @EnvironmentObject var model: AppModel
    let label: String

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What was the key outcome / deliverable?")
                .font(.headline)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...4)
                .focused($focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { model.saveOutput(text) }

            HStack {
                Text("optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { model.skipOutput() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.saveOutput(text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }
}
