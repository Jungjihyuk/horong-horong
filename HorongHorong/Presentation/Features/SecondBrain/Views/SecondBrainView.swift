import SwiftUI
import AppKit
import Inject

enum SecondBrainSection: String, CaseIterable, Identifiable {
    case quick
    case diary
    case todo
    case knowledge
    case works
    case refs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: return "Quick Note"
        case .diary: return "Diary"
        case .todo: return "Todo"
        case .knowledge: return "Knowledge"
        case .works: return "Works"
        case .refs: return "References"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "정리되지 않은 빠른 기록"
        case .diary: return "하루를 회고하는 일기"
        case .todo: return "미리알림과 연동되는 할 일"
        case .knowledge: return "배운 것 · 개념 정리"
        case .works: return "프로젝트 · 회사 문서"
        case .refs: return "자주 여는 링크와 쪽지"
        }
    }

    /// 팝오버 세그먼트 한 칸에 들어가는 짧은 이름.
    ///
    /// 허브 rail 은 «Quick Note» 를 그대로 쓰지만 팝오버는 폭이 360pt 라 다섯 칸에 나눠 담아야 한다.
    /// 영문 `label` 을 그대로 넣으면 칸마다 말줄임이 생겨 무엇인지 알아볼 수 없다.
    var shortLabel: String {
        switch self {
        case .quick: return "빠른 기록"
        case .diary: return "일기"
        case .todo: return "할 일"
        case .knowledge: return "지식"
        case .works: return "작업"
        case .refs: return "참고"
        }
    }

    /// 팝오버 세그먼트의 기호.
    ///
    /// 허브 rail 의 이모지(`glyph`)를 그대로 줄여 쓰면 줄이 지저분해진다 — ⚡·🧠 는 색이 있는
    /// 그림이고 ✓ 는 얇은 글자라, 13pt 로 나란히 놓으면 굵기도 색도 제각각이다.
    /// 바로 위 팝오버 탭바가 쓰는 SF Symbol 로 맞춰 한 벌로 보이게 한다.
    var symbol: String {
        switch self {
        case .quick: return "bolt.fill"
        case .diary: return "book.closed.fill"
        case .todo: return "checkmark.circle.fill"
        case .knowledge: return "brain.head.profile"
        case .works: return "hammer.fill"
        case .refs: return "pin.fill"
        }
    }

    /// 아직 화면이 없는 분류. 고를 수는 있고, 고르면 «준비 중» 안내가 뜬다.
    var isComingSoon: Bool {
        self == .knowledge || self == .works
    }

    /// 팝오버 「기록」 탭이 다루는 분류. References 는 팝오버용 요약 화면이 아직 없어 뺀다.
    static let popoverSections: [SecondBrainSection] = [.quick, .diary, .todo, .knowledge, .works]

    /// 저장된 값을 팝오버가 그릴 수 있는 분류로 읽는다.
    ///
    /// 허브와 저장 키를 함께 쓰기 때문에 팝오버가 모르는 값(References)이 들어올 수 있다.
    /// 그럴 때 Todo 로 «보여 주기만» 하고 **되돌려 저장하지는 않는다** — 팝오버를 한 번 열었다는
    /// 이유로 허브의 분류 선택이 지워지면 안 된다.
    static func popoverSection(rawValue: String) -> SecondBrainSection {
        guard let section = SecondBrainSection(rawValue: rawValue),
              popoverSections.contains(section) else { return .todo }
        return section
    }

    var glyph: String {
        switch self {
        case .quick: return "⚡"
        case .diary: return "📔"
        case .todo: return "✓"
        case .knowledge: return "🧠"
        case .works: return "🔧"
        case .refs: return "📌"
        }
    }

    var tint: Color {
        switch self {
        case .quick: return Color(red: 0.91, green: 0.54, blue: 0.24)
        case .diary: return Color(red: 0.78, green: 0.55, blue: 0.32)
        case .todo: return Color(red: 0.44, green: 0.62, blue: 0.38)
        case .knowledge: return Color(red: 0.72, green: 0.42, blue: 0.38)
        case .works: return Color(red: 0.52, green: 0.42, blue: 0.36)
        case .refs: return Color(red: 0.58, green: 0.48, blue: 0.62)
        }
    }
}

typealias MindSection = SecondBrainSection

struct SecondBrainView: View {
    @ObserveInjection var inject
    @State private var openedVaultSections: Set<SecondBrainSection> = []

    @Environment(AppState.self) private var appState
    @Environment(\.dependencies) private var dependencies
    @AppStorage(Constants.AppStorageKey.mindSection)
    private var sectionRaw: String = SecondBrainSection.todo.rawValue
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    @AppStorage(Constants.AppStorageKey.appIcon)
    private var appIconRaw: String = Constants.defaultAppIcon

    private var section: SecondBrainSection {
        SecondBrainSection(rawValue: sectionRaw) ?? .todo
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: appState.isRecordRailVisible ? 220 : 0, alignment: .leading)
                .clipped()
            Divider()
                .overlay(PopoverChrome.divider)
                .opacity(appState.isRecordRailVisible ? 1 : 0)
                .frame(width: appState.isRecordRailVisible ? 1 : 0)
            content
        }
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
        .id(popoverTheme)
        .animation(.easeInOut(duration: 0.24), value: appState.isRecordRailVisible)
        .enableInjection() 
        .onAppear { openedVaultSections.insert(section) }
        .onChange(of: sectionRaw) { _, _ in openedVaultSections.insert(section) }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                appIconView
                Text("내 머리속")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Text("상위 분류")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            ForEach(SecondBrainSection.allCases) { item in
                railItem(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PopoverChrome.surfaceAlt)
    }

    private func railItem(_ item: SecondBrainSection) -> some View {
        SecondBrainRailItem(item: item, isSelected: section == item) {
            sectionRaw = item.rawValue
        }
        .equatable()
    }

    @ViewBuilder
    private var appIconView: some View {
        let style = Constants.AppIconStyle.normalized(rawValue: appIconRaw)
        if let image = AppIconManager.image(for: style) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let dependencies {
                if openedVaultSections.contains(.knowledge) {
                    VaultBrowserView(kind: .knowledge, repository: dependencies.vaultRepository, locations: dependencies.vaultLocationGateway)
                        .opacity(section == .knowledge ? 1 : 0)
                        .disabled(section != .knowledge)
                        .accessibilityHidden(section != .knowledge)
                }
                if openedVaultSections.contains(.works) {
                    VaultBrowserView(kind: .works, repository: dependencies.vaultRepository, locations: dependencies.vaultLocationGateway)
                        .opacity(section == .works ? 1 : 0)
                        .disabled(section != .works)
                        .accessibilityHidden(section != .works)
                }
            }
        switch section {
        case .quick:
            if let repository = dependencies?.quickNoteRepository {
                QuickNoteBrowserView(repository: repository)
            }
        case .diary:
            if let dependencies {
                DiaryBrowserView(repository: dependencies.diaryRepository)
            }
        case .todo:
            if let repository = dependencies?.todoRepository {
                TodoBrowserView(repository: repository)
            }
        case .knowledge, .works:
            EmptyView()
        case .refs:
            if let repository = dependencies?.referenceRepository {
                ReferencesBrowserView(repository: repository)
            }
        }
        }
    }
}

/// 상위 분류 한 줄.
///
/// **독립 구조체인 이유**: 마우스가 올라온 줄만 따로 기억해야 하는데, 부모의 함수 안에서는
/// 줄마다 `@State` 를 가질 수 없다. 값만 받고 `Equatable` 이라 다른 줄이 바뀌어도 다시 그리지 않는다.
private struct SecondBrainRailItem: View, Equatable {
    let item: SecondBrainSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// 동작 클로저는 비교에서 뺀다. 넣으면 값이 그대로여도 매번 다르다고 판정된다.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(item.glyph)
                    .font(.system(size: 13))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(item.tint.opacity(isSelected ? 0.22 : 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(item.tint.opacity(isSelected ? 0.55 : 0.28), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.88) : PopoverChrome.ink)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.42) : PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // 고른 줄은 흰 카드, 마우스가 올라온 줄은 옅게. 글자색(`ink`)을 옅게 깔면
                    // 밝은 테마에서는 어두워지고 어두운 테마에서는 밝아져 어느 쪽에서도 «떠 보인다».
                    .fill(isSelected ? Color.white : (isHovering ? PopoverChrome.ink.opacity(0.06) : .clear))
                    .shadow(
                        color: isSelected ? Color.black.opacity(0.06) : .clear,
                        radius: 8,
                        y: 2
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(item.subtitle)
    }
}
