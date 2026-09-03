import SwiftUI

/// 온보딩 중 지금 강조할 요소를 알린다.
///
/// 팝오버·타이머 같은 화면은 컴패니언과 다른 창에 있어 값을 직접 넘길 수 없다.
/// 하나뿐인 공유 객체를 두고 각 화면이 자기 차례인지 확인하게 한다.
@MainActor
final class CompanionHighlightCenter: ObservableObject {
    static let shared = CompanionHighlightCenter()

    /// 강조할 대상 식별자. 대본의 `<!-- highlight: ... -->` 값이 그대로 들어온다.
    @Published private(set) var target: String?

    private init() {}

    func highlight(_ target: String?) {
        guard self.target != target else { return }
        self.target = target
    }

    // MARK: - 설정 카드 자동 찾기
    //
    // 카드마다 강조 id 를 손으로 달지 않는다.
    // 질문에서 뽑은 낱말을 놓아두면 화면에 그려진 카드들이 스스로 등록하고,
    // 그중 제목이 가장 잘 맞는 하나만 강조된다.

    private var questionTokens: [String] = []
    private var registeredCards: [String] = []

    static func cardID(_ title: String) -> String { "card:\(title)" }

    /// 답변에 맞는 카드를 찾기 시작한다. 페이지가 그려지기 전에 불러도 된다.
    func beginCardSearch(tokens: [String]) {
        questionTokens = tokens
        registeredCards = []
        target = nil
    }

    func endCardSearch() {
        questionTokens = []
        registeredCards = []
    }

    /// 화면에 나타난 카드가 자기 제목을 알린다.
    func registerCard(_ title: String) {
        guard !questionTokens.isEmpty else { return }
        guard !registeredCards.contains(title) else { return }
        registeredCards.append(title)

        guard let best = registeredCards.max(by: { score(for: $0) < score(for: $1) }),
              score(for: best) > 0 else {
            return
        }
        target = Self.cardID(best)
    }

    /// 제목이 질문 낱말을 얼마나 담고 있는지.
    private func score(for title: String) -> Int {
        let lowered = title.lowercased()
        return questionTokens.reduce(0) { $0 + (lowered.contains($1) ? $1.count : 0) }
    }

    func isHighlighted(_ id: String) -> Bool { target == id }

    /// 강조가 켜져 있는데 이 요소가 대상이 아니면 뒤로 물러나야 한다.
    func isDimmed(_ id: String) -> Bool {
        guard let target else { return false }
        return target != id
    }

    /// 컨테이너용. 안에 든 요소가 강조 대상이면 물러나지 않는다.
    /// 그렇지 않으면 자식까지 함께 흐려져 정작 강조한 버튼이 안 보인다.
    func isContainerDimmed(childPrefixes: [String]) -> Bool {
        guard let target else { return false }
        return !childPrefixes.contains { target.hasPrefix($0) }
    }
}

enum CompanionHighlightStyle {
    /// 앱 강조색(#D97706)과 같은 계열.
    static let tint = Color(red: 0.85, green: 0.46, blue: 0.04)
    /// 강조되지 않은 요소가 얼마나 물러날지.
    static let dimmedOpacity: Double = 0.32
}

/// 온보딩이 이 요소를 가리키는 동안 테두리를 그리고, 다른 곳을 가리키면 흐려진다.
private struct CompanionHighlightModifier: ViewModifier {
    let id: String
    @ObservedObject private var center = CompanionHighlightCenter.shared
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        let isOn = center.isHighlighted(id)
        let isDimmed = center.isDimmed(id)

        content
            .opacity(isDimmed ? CompanionHighlightStyle.dimmedOpacity : 1)
            .saturation(isDimmed ? 0.2 : 1)
            .overlay(ring(isOn: isOn))
            .animation(.easeOut(duration: 0.22), value: isOn)
            .animation(.easeOut(duration: 0.22), value: isDimmed)
            .onChange(of: isOn) { _, newValue in
                isPulsing = newValue
            }
    }

    /// 숨 쉬듯 커졌다 작아지는 테두리. 시선이 자연스럽게 끌리도록 반복한다.
    @ViewBuilder
    private func ring(isOn: Bool) -> some View {
        if isOn {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CompanionHighlightStyle.tint, lineWidth: 2)
                .shadow(color: CompanionHighlightStyle.tint.opacity(0.8), radius: isPulsing ? 10 : 3)
                .scaleEffect(isPulsing ? 1.05 : 0.99)
                .opacity(isPulsing ? 0.75 : 1)
                .padding(-4)
                .allowsHitTesting(false)
                .animation(
                    .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
        }
    }
}

/// 안에 강조 대상이 없을 때만 물러나는 영역.
private struct CompanionDimContainerModifier: ViewModifier {
    let childPrefixes: [String]
    @ObservedObject private var center = CompanionHighlightCenter.shared

    func body(content: Content) -> some View {
        let isDimmed = center.isContainerDimmed(childPrefixes: childPrefixes)
        content
            .opacity(isDimmed ? CompanionHighlightStyle.dimmedOpacity : 1)
            .saturation(isDimmed ? 0.2 : 1)
            .animation(.easeOut(duration: 0.22), value: isDimmed)
    }
}

extension View {
    /// 온보딩이 이 요소를 설명할 때 강조되고, 다른 곳을 설명할 때는 물러난다.
    func companionHighlight(_ id: String) -> some View {
        modifier(CompanionHighlightModifier(id: id))
    }

    /// 온보딩이 이 영역 *바깥* 을 설명할 때만 물러난다.
    func companionDimUnlessTargeting(_ childPrefixes: [String]) -> some View {
        modifier(CompanionDimContainerModifier(childPrefixes: childPrefixes))
    }
}

/// 말풍선 안의 `**강조**` 를 굵고 주황색으로 그린다.
///
/// 대본은 사람이 읽는 마크다운이라 별표를 쓴다. 그대로 두면 화면에 별표가 보이므로
/// 여기서 해석해 스타일로 바꾼다.
enum CompanionMarkdown {
    static func styled(_ text: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(text)
        }

        for run in attributed.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            attributed[run.range].foregroundColor = CompanionHighlightStyle.tint
            attributed[run.range].font = .system(size: 12.5, weight: .bold)
        }
        return attributed
    }
}
