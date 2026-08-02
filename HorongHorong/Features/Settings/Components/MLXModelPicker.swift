import SwiftUI

/// MLX 모델 선택기. `OllamaModelPicker` 와 같은 카드 목록 형태로 맞춰
/// 설정 화면에서 공급자를 바꿔도 고르는 방식이 달라지지 않게 한다.
///
/// Ollama 쪽과 달리 다운로드 버튼이 없다. MLX 가중치는 컴패니언 설정의 «내려받기» 가 맡고,
/// 여기서는 이미 받아 둔 모델인지만 표시한다.
struct MLXModelPicker: View {
    @Binding var model: String
    let options: [Constants.CompanionMLXModelOption]
    var isEnabled: Bool = true

    private var memoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("사용 가능 후보")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("M칩 통합 메모리 \(memoryGB)GB 기준")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(options) { option in
                    optionRow(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!isEnabled)
    }

    private func optionRow(_ option: Constants.CompanionMLXModelOption) -> some View {
        let isSelected = model == option.name
        let isTooLarge = option.minimumMemoryGB > memoryGB
        let isPrepared = MLXModelStore.isKnownPrepared(option.name)

        return HStack(spacing: 8) {
            Button {
                model = option.name
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(option.name.replacingOccurrences(of: "mlx-community/", with: ""))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        badge(for: option, isTooLarge: isTooLarge, isPrepared: isPrepared)
                    }
                    Text("\(option.detail) 권장 메모리: \(option.minimumMemoryGB)GB+.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("현재 선택된 모델")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .opacity(isTooLarge ? 0.55 : 1)
    }

    @ViewBuilder
    private func badge(
        for option: Constants.CompanionMLXModelOption,
        isTooLarge: Bool,
        isPrepared: Bool
    ) -> some View {
        if isTooLarge {
            tag("메모리 부족", color: .red)
        } else if isPrepared {
            tag("받음", color: .green)
        } else {
            tag("다운로드 필요", color: .orange)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}
