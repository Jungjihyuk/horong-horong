import SwiftUI

/// 섹션 헤더 + 그룹 제목 + 카드 컨테이너의 기본 단위. 한 페이지에 여러 개를 쌓는다.
struct SettingsGroupCard<Content: View>: View {
    @Environment(\.appearanceDensity) private var density

    var title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.cardHeaderSpacing) {
            if let title {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        // 호로롱이 답한 내용에 해당하는 카드가 스스로 강조된다.
        // 카드마다 식별자를 손으로 달지 않아도 되도록 여기 한 곳에서 처리한다.
        .companionHighlight(CompanionHighlightCenter.cardID(title ?? ""))
        .id(CompanionHighlightCenter.cardID(title ?? ""))
        .onAppear {
            if let title {
                CompanionHighlightCenter.shared.registerCard(title)
            }
        }
    }
}

/// 페이지 최상단 헤더: <h1> + 부제.
struct SettingsPageHeader: View {
    @Environment(\.appearanceDensity) private var density

    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: density.pageHeaderSpacing) {
            Text(title)
                .font(.system(size: density.pageTitleFontSize, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, density.pageHeaderBottomPadding)
    }
}

/// 페이지 공통 스크롤 컨테이너.
/// 카드는 detail 영역 전체에서 좌우 padding 만 빼고 자유롭게 늘어난다 (윈도우를 키우면 카드도 같이 커짐).
struct SettingsPageScroll<Content: View>: View {
    @Environment(\.appearanceDensity) private var density
    @ObservedObject private var highlightCenter = CompanionHighlightCenter.shared

    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: density.pageContentSpacing) {
                    content()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, density.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToHighlightedCard(using: proxy)
            }
            .onChange(of: highlightCenter.scrollTarget) { _, _ in
                scrollToHighlightedCard(using: proxy)
            }
        }
    }

    private func scrollToHighlightedCard(using proxy: ScrollViewProxy) {
        guard let target = highlightCenter.scrollTarget else { return }
        // 설정 페이지 전환과 카드 등록이 같은 런루프에 일어나므로 배치가 끝난 다음 이동한다.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }
}
