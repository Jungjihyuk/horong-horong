import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    @Binding var query: String

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List(selection: $selection) {
                ForEach(SettingsGroup.allCases) { group in
                    let visibleTabs = filteredTabs(in: group)
                    if !visibleTabs.isEmpty {
                        Section(group.rawValue) {
                            ForEach(visibleTabs) { tab in
                                Label(tab.label, systemImage: tab.systemIcon)
                                    .tag(tab)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
            versionCard
                .padding(12)
        }
        .frame(minWidth: SettingsTheme.sidebarWidth, idealWidth: SettingsTheme.sidebarWidth)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("설정 검색", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var versionCard: some View {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        return HStack(spacing: 10) {
            Image("HorongLogo")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("호롱호롱")
                    .font(.caption.bold())
                Text("v\(marketing)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func filteredTabs(in group: SettingsGroup) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return group.tabs }
        // 사용자가 공백으로 구분한 토큰 *모두* 가 매칭돼야 통과 (AND).
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return group.tabs.filter { tab in
            let haystack = tab.searchableHaystack
            return tokens.allSatisfy { token in
                haystack.localizedCaseInsensitiveContains(token)
            }
        }
    }
}
