import SwiftUI

/// `title/sub + 우측 컨트롤` 형식의 행 프리미티브. 디자인의 Row 컴포넌트에 대응.
struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var comingSoon: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        comingSoon: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.comingSoon = comingSoon
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout)
                    if comingSoon {
                        ComingSoonLabel()
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                trailing()
            }
            .disabled(comingSoon)
            .opacity(comingSoon ? 0.55 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            // 행 사이 구분선. 마지막 행은 부모가 마스크.
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.leading, 14)
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, comingSoon: Bool = false) {
        self.init(title, subtitle: subtitle, comingSoon: comingSoon) { EmptyView() }
    }
}

/// 세그먼티드 선택지. 디자인의 segmented 컴포넌트.
struct SettingsSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, label: String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// 단축키 표시(키캡). 추후 녹화 기능을 붙일 수 있도록 isRecording 옵션을 둔다.
struct HotkeyField: View {
    var keys: [String]
    var isRecording: Bool = false

    var body: some View {
        if isRecording {
            Text("● 키를 누르세요")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SettingsTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        } else {
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                    if idx > 0 {
                        Text("+")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(key)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}
