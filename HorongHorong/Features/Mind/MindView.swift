import SwiftUI
import AppKit

enum MindSection: String, CaseIterable, Identifiable {
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

struct MindView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.AppStorageKey.mindSection)
    private var sectionRaw: String = MindSection.todo.rawValue
    @AppStorage(Constants.AppStorageKey.popoverTheme)
    private var popoverTheme: String = Constants.defaultPopoverTheme
    @AppStorage(Constants.AppStorageKey.appIcon)
    private var appIconRaw: String = Constants.defaultAppIcon

    private var section: MindSection {
        MindSection(rawValue: sectionRaw) ?? .todo
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

            ForEach(MindSection.allCases) { item in
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

    private func railItem(_ item: MindSection) -> some View {
        let isSelected = section == item
        return Button {
            sectionRaw = item.rawValue
        } label: {
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
                    .fill(isSelected ? Color.white : .clear)
                    .shadow(
                        color: isSelected ? Color.black.opacity(0.06) : .clear,
                        radius: 8,
                        y: 2
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.subtitle)
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
        switch section {
        case .quick:
            QuickNoteBrowserView()
        case .diary:
            DiaryBrowserView()
        case .todo:
            TodoBrowserView()
        case .knowledge:
            VaultBrowserView(kind: .knowledge)
        case .works:
            VaultBrowserView(kind: .works)
        case .refs:
            ReferencesBrowserView()
        }
    }
}
