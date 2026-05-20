import Foundation
import Observation

/// 설정의 뉴스 탭에서 관리되는 멀티 소스 구성. runner.py 가 받는 `NewsSource` 모델로 그대로 변환 가능.
@Observable
final class NewsSourceStore: @unchecked Sendable {
    static let shared = NewsSourceStore()

    // MARK: - 모델

    enum YoutubeKind: Codable, Equatable {
        case channel(channelId: String)
        case playlist(playlistId: String)
    }

    struct YoutubeItem: Codable, Identifiable, Equatable {
        let id: UUID
        var kind: YoutubeKind
        /// 사용자 친화 표시명. 없으면 ID 그대로 노출.
        var displayName: String

        init(id: UUID = UUID(), kind: YoutubeKind, displayName: String = "") {
            self.id = id
            self.kind = kind
            self.displayName = displayName
        }

        var rawIdentifier: String {
            switch kind {
            case .channel(let channelId): return channelId
            case .playlist(let playlistId): return playlistId
            }
        }
    }

    struct RSSFeed: Codable, Identifiable, Equatable {
        let id: UUID
        var url: String
        var title: String

        init(id: UUID = UUID(), url: String, title: String = "") {
            self.id = id
            self.url = url
            self.title = title
        }
    }

    private struct Snapshot: Codable {
        var youtube: [YoutubeItem]
        var rss: [RSSFeed]
        var googleNewsEnabled: Bool
        var hackerNewsEnabled: Bool
        var yozmITEnabled: Bool
    }

    // MARK: - 상태

    private(set) var youtubeItems: [YoutubeItem] = []
    private(set) var rssFeeds: [RSSFeed] = []
    var googleNewsEnabled: Bool { didSet { save() } }
    var hackerNewsEnabled: Bool { didSet { save() } }
    var yozmITEnabled: Bool { didSet { save() } }

    // MARK: - Init / 영속

    private init() {
        // 기본값: 모든 단일 소스 OFF, 컬렉션 비어있음.
        googleNewsEnabled = false
        hackerNewsEnabled = false
        yozmITEnabled = false
        load()
        migrateLegacyYoutubeIfNeeded()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Constants.NewsStorageKey.sources),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        youtubeItems = snapshot.youtube
        rssFeeds = snapshot.rss
        googleNewsEnabled = snapshot.googleNewsEnabled
        hackerNewsEnabled = snapshot.hackerNewsEnabled
        yozmITEnabled = snapshot.yozmITEnabled
    }

    private func save() {
        let snapshot = Snapshot(
            youtube: youtubeItems,
            rss: rssFeeds,
            googleNewsEnabled: googleNewsEnabled,
            hackerNewsEnabled: hackerNewsEnabled,
            yozmITEnabled: yozmITEnabled
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Constants.NewsStorageKey.sources)
        }
    }

    /// 기존 NewsView 에서 쓰던 CSV 형식의 youtube channel IDs 를 새 모델로 1회 이전.
    private func migrateLegacyYoutubeIfNeeded() {
        let migrationKey = "news.sources.migration.v1"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        if let raw = defaults.string(forKey: Constants.NewsStorageKey.youtubeChannelIds) {
            let ids = raw.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for id in ids where !youtubeItems.contains(where: { $0.rawIdentifier == id }) {
                youtubeItems.append(YoutubeItem(kind: .channel(channelId: id), displayName: id))
            }
            if !ids.isEmpty { save() }
        }
        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Mutation API

    func addYoutubeChannel(input rawInput: String, displayName: String = "") -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let channelId = Self.extractYoutubeChannelId(from: trimmed)
        guard !channelId.isEmpty else { return false }
        guard !youtubeItems.contains(where: {
            if case .channel(let id) = $0.kind { return id == channelId }
            return false
        }) else { return false }
        let resolvedName = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? channelId : displayName
        youtubeItems.append(YoutubeItem(kind: .channel(channelId: channelId), displayName: resolvedName))
        save()
        return true
    }

    func addYoutubePlaylist(input rawInput: String, displayName: String = "") -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let playlistId = Self.extractYoutubePlaylistId(from: trimmed)
        guard !playlistId.isEmpty else { return false }
        guard !youtubeItems.contains(where: {
            if case .playlist(let id) = $0.kind { return id == playlistId }
            return false
        }) else { return false }
        let resolvedName = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? playlistId : displayName
        youtubeItems.append(YoutubeItem(kind: .playlist(playlistId: playlistId), displayName: resolvedName))
        save()
        return true
    }

    func removeYoutube(id: UUID) {
        youtubeItems.removeAll { $0.id == id }
        save()
    }

    func clearAllYoutube() {
        guard !youtubeItems.isEmpty else { return }
        youtubeItems.removeAll()
        save()
    }

    func addRSS(url: String, title: String = "") -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return false }
        guard !rssFeeds.contains(where: { $0.url == trimmed }) else { return false }
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? trimmed : title
        rssFeeds.append(RSSFeed(url: trimmed, title: resolvedTitle))
        save()
        return true
    }

    func removeRSS(id: UUID) {
        rssFeeds.removeAll { $0.id == id }
        save()
    }

    func clearAllRSS() {
        guard !rssFeeds.isEmpty else { return }
        rssFeeds.removeAll()
        save()
    }

    // MARK: - 파이프라인 변환

    /// runner.py 가 받는 NewsSource 배열로 변환. 비활성 소스는 enabled=false 로 표시 (백엔드가 무시).
    func toPipelineSources() -> [NewsSource] {
        var sources: [NewsSource] = []

        // YouTube — channel 과 playlist 를 분리한 채로 하나의 NewsSource 로 묶음.
        let channelIds = youtubeItems.compactMap { item -> String? in
            if case .channel(let id) = item.kind { return id }
            return nil
        }
        let playlists = youtubeItems.compactMap { item -> NewsPlaylist? in
            if case .playlist(let id) = item.kind {
                return NewsPlaylist(name: item.displayName, playlistId: id)
            }
            return nil
        }
        if !channelIds.isEmpty || !playlists.isEmpty {
            sources.append(NewsSource(
                type: "youtube",
                enabled: true,
                channelId: nil,
                channelIds: channelIds.isEmpty ? nil : channelIds,
                playlists: playlists.isEmpty ? nil : playlists,
                keywords: nil,
                profiles: nil
            ))
        }

        if googleNewsEnabled {
            sources.append(NewsSource(type: "google_news", enabled: true, keywords: nil))
        }
        if hackerNewsEnabled {
            sources.append(NewsSource(type: "hacker_news", enabled: true))
        }
        if yozmITEnabled {
            sources.append(NewsSource(type: "yozm_it", enabled: true, keywords: nil))
        }
        if !rssFeeds.isEmpty {
            let urls = rssFeeds.map(\.url)
            sources.append(NewsSource(
                type: "rss",
                enabled: true,
                channelIds: urls,
                keywords: nil
            ))
        }
        return sources
    }

    // MARK: - URL 파싱

    /// YouTube 채널 URL 또는 ID 입력에서 channelId 를 추출. 실패 시 입력 그대로 반환.
    static func extractYoutubeChannelId(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed) {
            let components = url.pathComponents
            if let idx = components.firstIndex(of: "channel"), components.indices.contains(idx + 1) {
                return components[idx + 1]
            }
            if let last = components.last(where: { $0.hasPrefix("@") }) {
                return last
            }
            if let last = components.last, last.hasPrefix("UC") {
                return last
            }
        }
        return trimmed
    }

    /// YouTube 재생목록 URL 또는 ID 입력에서 playlistId 추출. URL 쿼리에 list= 가 있으면 우선.
    static func extractYoutubePlaylistId(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let listItem = components.queryItems?.first(where: { $0.name == "list" })?.value {
            return listItem
        }
        if trimmed.hasPrefix("PL") || trimmed.hasPrefix("UU") || trimmed.hasPrefix("OL") {
            return trimmed
        }
        return trimmed
    }
}
