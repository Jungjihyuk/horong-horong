import SwiftUI

enum SettingsTheme {
    static let sidebarWidth: CGFloat = 240
    /// 페이지 콘텐츠 가로폭 상한. 최소 윈도우(920) - 사이드바(240) = detail 영역 ~680 보다 살짝 작게 잡아
    /// 어느 크기에서도 캡이 활성화돼 카드 폭이 변하지 않게 한다.
    static let contentMaxWidth: CGFloat = 680
    static let windowMinSize = CGSize(width: 920, height: 640)
    static let windowDefaultSize = CGSize(width: 980, height: 680)

    static let accent = Color(red: 0.85, green: 0.46, blue: 0.04)        // #D97706
    static let accentWarm = Color(red: 0.85, green: 0.47, blue: 0.34)    // #D97757

    static let accentPalette: [(name: String, color: Color)] = [
        ("호롱불", Color(red: 0.85, green: 0.46, blue: 0.04)),
        ("대나무", Color(red: 0.12, green: 0.54, blue: 0.38)),
        ("청자",   Color(red: 0.14, green: 0.39, blue: 0.92)),
        ("오디",   Color(red: 0.58, green: 0.20, blue: 0.92)),
    ]
}

extension Color {
    static let horongCard = Color(nsColor: .windowBackgroundColor).opacity(0.6)
    static let horongCardBorder = Color.primary.opacity(0.08)
    static let horongMutedText = Color.secondary
}

/// 백엔드 로직이 아직 없는 컨트롤 옆에 다는 작은 라벨.
struct ComingSoonLabel: View {
    var body: some View {
        Text("준비 중")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
    }
}
