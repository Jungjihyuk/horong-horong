import XCTest
@testable import 호롱호롱

/// 타임라인도 보관함처럼 **디스크가 근거**다. 임시 폴더에 파이썬이 쓰는 것과 같은 모양의
/// 상태 JSON 을 만들어, 폴더 훑기(`NewsTimelineStore`)와 디코딩까지 함께 확인한다.
@MainActor
final class NewsTimelineTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("news-timeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: timelineDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        base = nil
    }

    private var timelineDirectory: URL {
        base.appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("timeline", isDirectory: true)
    }

    /// 파이썬 계약은 snake_case 다(`Contracts/news/timeline_state.schema.json`).
    private func write(categoryId: String, json: String) throws {
        try json.write(
            to: timelineDirectory.appendingPathComponent("\(categoryId).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func sampleJSON(categoryId: String, categoryLabel: String) -> String {
        """
        {
          "schema_version": 1,
          "category_id": "\(categoryId)",
          "category_label": "\(categoryLabel)",
          "date_from": "2026-02-22",
          "date_to": "2026-04-30",
          "generated_at": "2026-09-08T21:00:00",
          "months": [
            {
              "month_key": "2026-02",
              "input_hash": "sha256:aaa",
              "synthesized_at": "2026-09-08T21:00:00",
              "provider": "ollama",
              "prompt_version": 2,
              "summary": "2월 종합.",
              "key_terms": ["관세"],
              "is_turning_point": false,
              "axis_events": [
                {
                  "event_id": "e1",
                  "date": "2026-02-22",
                  "title": "미 대법원 관세 무효화",
                  "url": "https://example.com/a",
                  "importance": 83,
                  "bullets": ["실물 경제의 역습"],
                  "tags": ["관세"],
                  "rank": null,
                  "why_it_matters": "판결이 흐름을 바꿨다."
                }
              ],
              "detail_events": []
            },
            {
              "month_key": "2026-04",
              "input_hash": "sha256:bbb",
              "synthesized_at": "2026-09-08T21:00:00",
              "provider": "ollama",
              "prompt_version": 2,
              "summary": "4월 종합.",
              "key_terms": ["유가", "증시"],
              "is_turning_point": true,
              "axis_events": [
                {
                  "event_id": "e2",
                  "date": "2026-04-16",
                  "title": "AI칩 공개",
                  "url": "",
                  "importance": 88,
                  "bullets": [],
                  "tags": [],
                  "rank": null,
                  "why_it_matters": ""
                }
              ],
              "detail_events": [
                {
                  "event_id": "e3",
                  "date": "2026-04-08",
                  "title": "휴전 기대",
                  "url": "https://example.com/b",
                  "importance": 83,
                  "bullets": ["이란 소통채널 폐쇄"],
                  "tags": ["휴전"],
                  "rank": 4,
                  "why_it_matters": ""
                }
              ]
            }
          ],
          "overview": {
            "input_hash": "sha256:ccc",
            "summary": "전체 흐름.",
            "emphasis_keywords": ["국채금리", "유가"],
            "turning_point_count": 1
          },
          "warnings": []
        }
        """
    }

    // MARK: - 디코딩

    /// snake_case 계약이 Domain 값 타입으로 옮겨진다.
    func testLoadTimelines_decodesSnakeCaseContract() throws {
        try write(categoryId: "금리-거시경제", json: sampleJSON(
            categoryId: "금리-거시경제", categoryLabel: "금리/거시경제"
        ))

        let timelines = NewsTimelineStore.loadTimelines(dataBasePath: base.path)

        XCTAssertEqual(timelines.count, 1)
        let timeline = try XCTUnwrap(timelines.first)
        XCTAssertEqual(timeline.categoryLabel, "금리/거시경제")
        XCTAssertEqual(timeline.months.count, 2)
        XCTAssertEqual(timeline.overview.emphasisKeywords, ["국채금리", "유가"])

        let february = try XCTUnwrap(timeline.months.first)
        XCTAssertEqual(february.keyTerms, ["관세"])
        XCTAssertEqual(february.axisEvents.first?.whyItMatters, "판결이 흐름을 바꿨다.")
        XCTAssertNil(february.axisEvents.first?.rank, "축 사건은 순위를 갖지 않는다")
    }

    /// «N개 시점» 은 축과 세부를 합친 수다.
    func testTotalEventCount_countsAxisAndDetail() throws {
        try write(categoryId: "macro", json: sampleJSON(categoryId: "macro", categoryLabel: "거시"))

        let timeline = try XCTUnwrap(
            NewsTimelineStore.loadTimelines(dataBasePath: base.path).first
        )

        XCTAssertEqual(timeline.totalEventCount, 3)
        XCTAssertEqual(timeline.turningPointMonthKeys, ["2026-04"])
    }

    /// 폴더가 없어도 죽지 않는다. 타임라인은 아직 안 만들었을 수 있다.
    func testLoadTimelines_missingDirectory_returnsEmpty() {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString)", isDirectory: true)

        XCTAssertTrue(NewsTimelineStore.loadTimelines(dataBasePath: empty.path).isEmpty)
    }

    /// 깨진 JSON 한 개가 나머지를 막지 않는다.
    func testLoadTimelines_corruptFile_isSkipped() throws {
        try write(categoryId: "ok", json: sampleJSON(categoryId: "ok", categoryLabel: "정상"))
        try write(categoryId: "broken", json: "{ 이건 JSON 이 아니다")

        let timelines = NewsTimelineStore.loadTimelines(dataBasePath: base.path)

        XCTAssertEqual(timelines.map(\.categoryId), ["ok"])
    }

    // MARK: - 봉인 판정 (R2)

    /// 봉인 여부는 **저장하지 않고 계산한다.** 쓰기 없이 자정만 지나도 바뀌는 값이라
    /// 저장하면 틀린다. 파이썬 `timeline/state.py::is_sealed` 와 같은 판단이어야 한다.
    func testIsSealed_comparesAgainstGivenNow() throws {
        let month = NewsTimelineMonth(
            monthKey: "2026-08",
            synthesizedAt: "2026-09-08T21:00:00",
            summary: "",
            keyTerms: [],
            isTurningPoint: false,
            axisEvents: [],
            detailEvents: []
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

        let inSeptember = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))
        )
        let inAugust = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))
        )

        XCTAssertTrue(month.isSealed(now: inSeptember, calendar: calendar))
        XCTAssertFalse(
            month.isSealed(now: inAugust, calendar: calendar),
            "같은 달이면 아직 사건이 더 붙을 수 있다"
        )
    }

    // MARK: - ViewModel

    /// 목록의 근거는 디스크다. 파이프라인 완료 알림이 다시 읽으라는 신호다.
    func testViewModel_reload_selectsFirstTimelineByDefault() throws {
        try write(categoryId: "a", json: sampleJSON(categoryId: "a", categoryLabel: "가"))

        let viewModel = NewsTimelineViewModel()
        XCTAssertTrue(viewModel.isEmpty)

        viewModel.reload(dataBasePath: base.path)

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.selectedTimeline?.categoryId, "a")
    }

    /// 고른 분야의 파일이 사라지면 선택이 남아 빈 화면이 되지 않아야 한다.
    func testViewModel_selectedCategoryDisappears_fallsBackToFirst() throws {
        try write(categoryId: "a", json: sampleJSON(categoryId: "a", categoryLabel: "가"))
        try write(categoryId: "b", json: sampleJSON(categoryId: "b", categoryLabel: "나"))

        let viewModel = NewsTimelineViewModel()
        viewModel.reload(dataBasePath: base.path)
        viewModel.select("b")
        XCTAssertEqual(viewModel.selectedTimeline?.categoryId, "b")

        try FileManager.default.removeItem(
            at: timelineDirectory.appendingPathComponent("b.json")
        )
        viewModel.reload(dataBasePath: base.path)

        XCTAssertEqual(viewModel.selectedTimeline?.categoryId, "a")
    }
}
