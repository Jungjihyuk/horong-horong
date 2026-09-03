import SwiftUI

// MARK: - 새 소스 추가 시트

/// "+ 소스 추가" 버튼이 띄우는 시트. 타입 선택 → 입력 폼.
struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = NewsSourceStore.shared
    @State private var selectedType: SourceKind = .youtubeChannel

    @State private var inputURL: String = ""
    @State private var inputName: String = ""

    enum SourceKind: String, CaseIterable, Identifiable {
        case youtubeChannel
        case youtubePlaylist
        case googleNews
        case hackerNews
        case yozmIT
        case rss

        var id: String { rawValue }
        /// 백엔드 connector 가 아직 없는 소스. UI 에는 노출하되 추가는 막아 혼동을 방지.
        var isComingSoon: Bool {
            switch self {
            case .hackerNews, .rss: return true
            default: return false
            }
        }
        var label: String {
            let base: String
            switch self {
            case .youtubeChannel:  base = "YouTube 채널"
            case .youtubePlaylist: base = "YouTube 재생목록"
            case .googleNews:      base = "Google News"
            case .hackerNews:      base = "Hacker News"
            case .yozmIT:          base = "YOZM IT"
            case .rss:             base = "RSS 피드"
            }
            return isComingSoon ? "\(base) (준비 중)" : base
        }
        var icon: SourceChipIcon {
            switch self {
            case .youtubeChannel, .youtubePlaylist: return .youtube
            case .googleNews: return .googleNews
            case .hackerNews: return .hackerNews
            case .yozmIT:     return .yozmIT
            case .rss:        return .rss
            }
        }
        var needsInput: Bool {
            switch self {
            case .youtubeChannel, .youtubePlaylist, .rss: return true
            case .googleNews, .hackerNews, .yozmIT:       return false
            }
        }
        var inputPlaceholder: String {
            switch self {
            case .youtubeChannel:  return "https://www.youtube.com/@channel 또는 UC... 채널 ID"
            case .youtubePlaylist: return "https://www.youtube.com/playlist?list=PL... 또는 PL... ID"
            case .rss:             return "https://example.com/feed.xml"
            default:               return ""
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("소스 추가")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("소스 종류")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedType) {
                    ForEach(SourceKind.allCases) { kind in
                        Label(kind.label, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedType.isComingSoon {
                Text(disabledNote)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.08))
                    )
            } else if selectedType.needsInput {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL 또는 ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(selectedType.inputPlaceholder, text: $inputURL)
                        .textFieldStyle(.roundedBorder)
                    Text("표시명 (선택)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("예: Anthropic, Apple Developer", text: $inputName)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                Text(disabledNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("추가") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var disabledNote: String {
        if selectedType.isComingSoon {
            return "해당 소스 collector 는 아직 구현 전이라 추가해도 수집되지 않습니다. (HN / RSS connector 추가 후 활성화 예정)"
        }
        switch selectedType {
        case .googleNews: return store.googleNewsEnabled ? "이미 활성화돼 있어요." : "Google News 소스를 활성화합니다. 관심 키워드가 자동 적용됩니다."
        case .hackerNews: return store.hackerNewsEnabled ? "이미 활성화돼 있어요." : "Hacker News 첫 페이지를 수집합니다."
        case .yozmIT:     return store.yozmITEnabled ? "이미 활성화돼 있어요." : "YOZM IT 한국 IT 뉴스를 수집합니다. 관심 키워드가 자동 적용됩니다."
        default:          return ""
        }
    }

    private var canAdd: Bool {
        if selectedType.isComingSoon { return false }
        switch selectedType {
        case .youtubeChannel, .youtubePlaylist, .rss:
            return !inputURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .googleNews: return !store.googleNewsEnabled
        case .hackerNews: return !store.hackerNewsEnabled
        case .yozmIT:     return !store.yozmITEnabled
        }
    }

    private func add() {
        switch selectedType {
        case .youtubeChannel:
            _ = store.addYoutubeChannel(input: inputURL, displayName: inputName)
        case .youtubePlaylist:
            _ = store.addYoutubePlaylist(input: inputURL, displayName: inputName)
        case .rss:
            _ = store.addRSS(url: inputURL, title: inputName)
        case .googleNews: store.googleNewsEnabled = true
        case .hackerNews: store.hackerNewsEnabled = true
        case .yozmIT:     store.yozmITEnabled = true
        }
        dismiss()
    }
}

// MARK: - 소스 상세 (chip 클릭 시)

enum SourceDetailKind: Identifiable {
    case youtube
    case rss
    var id: String {
        switch self {
        case .youtube: return "youtube"
        case .rss:     return "rss"
        }
    }
}

struct SourceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = NewsSourceStore.shared
    let kind: SourceDetailKind

    @State private var newURL: String = ""
    @State private var newName: String = ""
    @State private var youtubeAddingPlaylist: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }

            switch kind {
            case .youtube: youtubeBody
            case .rss:     rssBody
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }

    private var title: String {
        switch kind {
        case .youtube: return "YouTube 채널·재생목록"
        case .rss:     return "RSS 피드"
        }
    }

    // MARK: - YouTube

    private var youtubeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $youtubeAddingPlaylist) {
                Text("채널").tag(false)
                Text("재생목록").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            TextField(youtubeAddingPlaylist
                      ? "재생목록 URL 또는 ID"
                      : "채널 URL 또는 ID", text: $newURL)
                .textFieldStyle(.roundedBorder)
            TextField("표시명 (선택)", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("추가") {
                    if youtubeAddingPlaylist {
                        _ = store.addYoutubePlaylist(input: newURL, displayName: newName)
                    } else {
                        _ = store.addYoutubeChannel(input: newURL, displayName: newName)
                    }
                    newURL = ""
                    newName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            if store.youtubeItems.isEmpty {
                Text("등록된 채널·재생목록이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.youtubeItems) { item in
                            youtubeRow(item)
                        }
                    }
                }
            }
        }
    }

    private func youtubeRow(_ item: NewsSourceStore.YoutubeItem) -> some View {
        HStack(spacing: 8) {
            Text(kindLabel(item.kind))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.callout)
                Text(item.rawIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive) {
                store.removeYoutube(id: item.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func kindLabel(_ kind: NewsSourceStore.YoutubeKind) -> String {
        switch kind {
        case .channel:  return "채널"
        case .playlist: return "재생목록"
        }
    }

    // MARK: - RSS

    private var rssBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("RSS URL (https://...)", text: $newURL)
                .textFieldStyle(.roundedBorder)
            TextField("표시명 (선택)", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("추가") {
                    _ = store.addRSS(url: newURL, title: newName)
                    newURL = ""
                    newName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            if store.rssFeeds.isEmpty {
                Text("등록된 RSS 피드가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.rssFeeds) { feed in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.title)
                                        .font(.callout)
                                    Text(feed.url)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    store.removeRSS(id: feed.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
