import SwiftUI

struct QuickMemoView: View {
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var memoContent: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("호롱호롱 퀵 메모")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            TextEditor(text: $memoContent)
                .font(.body)
                .focused($isTextFieldFocused)
                .frame(minHeight: 80, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if memoContent.isEmpty {
                        Text("빠르게 메모하세요...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16)

            HStack {
                Spacer()
                Button("취소") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("저장") {
                    guard !memoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(memoContent)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: Constants.quickMemoPanelWidth)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
