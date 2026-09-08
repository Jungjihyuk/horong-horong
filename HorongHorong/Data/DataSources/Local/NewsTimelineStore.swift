import Foundation

/// `data/timeline/*.json` 을 읽어 `NewsTimeline` 으로 옮긴다.
///
/// **`NewsReportArchiveStore` 를 넓히지 않고 따로 둔 이유**: 근거가 되는 파일이 다르다.
/// 보관함은 `data/reports/*.md`(리포트 한 편), 이쪽은 `data/timeline/*.json`(분야 한 개의
/// 누적 상태)이다. 하나가 없어도 다른 하나는 있어야 하고, 갱신 시점도 다르다.
///
/// 파이썬 계약은 snake_case 라 `convertFromSnakeCase` 로 받는다. 계약 원본은
/// `Contracts/news/timeline_state.schema.json` 이며, 파이썬 쪽 단위 테스트가 그 파일과
/// pydantic 모델의 일치를 강제한다.
enum NewsTimelineStore {
    static func timelineDirectoryURL(dataBasePath: String) -> URL {
        URL(fileURLWithPath: dataBasePath, isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("timeline", isDirectory: true)
    }

    /// 폴더를 훑어 분야별 타임라인을 모두 읽는다. 폴더가 없으면 빈 배열이다.
    static func loadTimelines(
        dataBasePath: String,
        fileManager: FileManager = .default
    ) -> [NewsTimeline] {
        let directory = timelineDirectoryURL(dataBasePath: dataBasePath)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap(load(at:))
            // 사건이 많은 분야를 앞에 둔다. 같으면 이름순으로 고정해 순서가 흔들리지 않게 한다.
            .sorted {
                if $0.totalEventCount != $1.totalEventCount {
                    return $0.totalEventCount > $1.totalEventCount
                }
                return $0.categoryLabel < $1.categoryLabel
            }
    }

    static func load(at url: URL) -> NewsTimeline? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(TimelineStatePayload.self, from: data) else {
            return nil
        }
        return payload.toDomain()
    }
}

// MARK: - 디코딩 전용 표현

/// 파일 모양 그대로의 중간 표현. Domain 값 타입과 분리해 두면 파이썬 쪽 계약이 늘어나도
/// 화면이 쓰는 타입은 그대로 둘 수 있다.
struct TimelineStatePayload: Decodable {
    struct Event: Decodable {
        let eventId: String
        let date: String
        let title: String
        let url: String?
        let importance: Int?
        let bullets: [String]?
        let tags: [String]?
        let rank: Int?
        let whyItMatters: String?
    }

    struct Month: Decodable {
        let monthKey: String
        let synthesizedAt: String?
        let summary: String?
        let keyTerms: [String]?
        let isTurningPoint: Bool?
        let axisEvents: [Event]?
        let detailEvents: [Event]?
    }

    struct Overview: Decodable {
        let summary: String?
        let emphasisKeywords: [String]?
        let turningPointCount: Int?
    }

    let categoryId: String
    let categoryLabel: String
    let dateFrom: String?
    let dateTo: String?
    let months: [Month]?
    let overview: Overview?
    let warnings: [String]?

    /// 한 덩어리로 쓰면 Swift 타입 체커가 시간 안에 못 푼다(실제로 SourceKit 이
    /// «unable to type-check in reasonable time» 을 냈다). 단계별로 쪼갠다.
    func toDomain() -> NewsTimeline {
        let domainMonths: [NewsTimelineMonth] = (months ?? []).map(Self.month)
        let domainOverview: NewsTimelineOverview = overview.map(Self.overview) ?? .empty

        return NewsTimeline(
            categoryId: categoryId,
            categoryLabel: categoryLabel,
            dateFrom: dateFrom ?? "",
            dateTo: dateTo ?? "",
            months: domainMonths,
            overview: domainOverview,
            warnings: warnings ?? []
        )
    }

    private static func month(_ raw: Month) -> NewsTimelineMonth {
        let axis: [NewsTimelineEvent] = (raw.axisEvents ?? []).map(Self.event)
        let detail: [NewsTimelineEvent] = (raw.detailEvents ?? []).map(Self.event)

        return NewsTimelineMonth(
            monthKey: raw.monthKey,
            synthesizedAt: raw.synthesizedAt ?? "",
            summary: raw.summary ?? "",
            keyTerms: raw.keyTerms ?? [],
            isTurningPoint: raw.isTurningPoint ?? false,
            axisEvents: axis,
            detailEvents: detail
        )
    }

    private static func overview(_ raw: Overview) -> NewsTimelineOverview {
        NewsTimelineOverview(
            summary: raw.summary ?? "",
            emphasisKeywords: raw.emphasisKeywords ?? [],
            turningPointCount: raw.turningPointCount ?? 0
        )
    }

    private static func event(_ raw: Event) -> NewsTimelineEvent {
        NewsTimelineEvent(
            eventId: raw.eventId,
            date: raw.date,
            title: raw.title,
            url: raw.url ?? "",
            importance: raw.importance ?? 0,
            bullets: raw.bullets ?? [],
            tags: raw.tags ?? [],
            rank: raw.rank,
            whyItMatters: raw.whyItMatters ?? ""
        )
    }
}
