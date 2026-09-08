import SwiftUI

struct GoalRefinementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GoalRefinementEditorViewModel
    let onSaved: () -> Void

    init(viewModel: GoalRefinementEditorViewModel, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.isTodo ? "할 일 구체화" : "주간 목표 구체화")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Text(viewModel.example.hasPrefix("예:") ? viewModel.example : "예: \(viewModel.example)")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))

            TextField("제목", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
            TextField(viewModel.isTodo ? "메모 (선택)" : "측정 기준 (선택)", text: $viewModel.detail)
                .textFieldStyle(.roundedBorder)

            if viewModel.isTodo {
                Toggle("시작 시간", isOn: $viewModel.hasStartDate)
                if viewModel.hasStartDate {
                    DatePicker("", selection: $viewModel.startDate)
                        .labelsHidden()
                }
            }
            Toggle("마감", isOn: $viewModel.hasDueDate)
            if viewModel.hasDueDate {
                DatePicker("", selection: $viewModel.dueDate)
                    .labelsHidden()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("저장") {
                    guard viewModel.save() else { return }
                    onSaved()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(PopoverChrome.surface)
    }
}
