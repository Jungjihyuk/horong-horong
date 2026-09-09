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
          "schema_version": 2,
          "category_id": "\(categoryId)",
          "category_label": "\(categoryLabel)",
          "axis_limit": 3,
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
              "axis_events": [
                {
                  "event_id": "e1",
                  "date": "2026-02-22",
                  "title": "미 대법원 관세 무효화",
                  "url": "https://example.com/a",
                  "importance": 83,
                  "importance_assessment": {
                    "change_magnitude": 20,
                    "impact_scope": 20,
                    "durability": 15,
                    "trajectory_power": 18,
                    "evidence_strength": 10,
                    "reason": "정책 경로를 바꾼 판결이다."
                  },
                  "bullets": ["실물 경제의 역습"],
                  "tags": ["관세"],
                  "why_it_matters": "판결이 흐름을 바꿨다.",
                  "turning_point_reason": ""
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
              "axis_events": [
                {
                  "event_id": "e2",
                  "date": "2026-04-16",
                  "title": "AI칩 공개",
                  "url": "",
                  "importance": 88,
                  "bullets": [],
                  "tags": [],
                  "why_it_matters": "",
                  "turning_point_reason": "기대가 실제 금리 상승으로 바뀌었다."
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
                  "why_it_matters": "",
                  "turning_point_reason": ""
                }
              ]
            }
          ],
          "overview": {
            "input_hash": "sha256:ccc",
            "summary": "전체 흐름.",
            "emphasis_keywords": ["국채금리", "유가"]
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
        XCTAssertEqual(timeline.axisLimit, 3)
        XCTAssertEqual(timeline.months.count, 2)
        XCTAssertEqual(timeline.overview.emphasisKeywords, ["국채금리", "유가"])

        let february = try XCTUnwrap(timeline.months.first)
        XCTAssertEqual(february.keyTerms, ["관세"])
        XCTAssertEqual(february.axisEvents.first?.whyItMatters, "판결이 흐름을 바꿨다.")
        XCTAssertEqual(february.axisEvents.first?.importanceAssessment?.trajectoryPower, 18)
        XCTAssertEqual(february.axisEvents.first?.importanceAssessment?.total, 83)
    }

    /// 구버전 상태는 상세 근거가 없어도 열리고 대표 최대치는 3으로 보정한다.
    func testLoadTimelines_versionOneState_usesCompatibleDefaults() throws {
        let json = """
        {
          "schema_version": 1,
          "category_id": "legacy",
          "category_label": "구버전",
          "months": [{
            "month_key": "2026-09",
            "input_hash": "old",
            "is_turning_point": true,
            "axis_events": [{
              "event_id": "old-event",
              "date": "2026-09-01",
              "title": "기존 사건",
              "importance": 72,
              "rank": null
            }]
          }]
        }
        """
        try write(categoryId: "legacy", json: json)

        let timeline = try XCTUnwrap(
            NewsTimelineStore.loadTimelines(dataBasePath: base.path).first
        )

        XCTAssertEqual(timeline.axisLimit, 3)
        XCTAssertNil(timeline.months[0].axisEvents[0].importanceAssessment)
        XCTAssertEqual(timeline.turningPointCount, 0, "월 단위 구버전 표시는 사건 전환점으로 승격하지 않는다")
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

// MARK: - 주제 제안과 사용자 트리거 생성

/// 게이트웨이 fake. 실제 러너 프로세스를 띄우지 않는다.
@MainActor
private final class FakeTimelineGateway: NewsTimelineGateway {
    var providerDisplayName: String = "fake · test-model"
    var suggestions: [NewsTimelineSuggestion] = []
    var suggestError: Error?
    var buildError: Error?
    private(set) var builtLabels: [String] = []
    private(set) var builtAxisLimits: [Int] = []
    /// 만들기가 성공했을 때 상태 파일을 쓰기 위한 훅.
    var onBuild: ((String) -> Void)?

    func suggestTopics(dataBasePath: String) async throws -> [NewsTimelineSuggestion] {
        if let suggestError { throw suggestError }
        return suggestions
    }

    func buildTimeline(label: String, axisLimit: Int, dataBasePath: String) async throws {
        if let buildError { throw buildError }
        builtLabels.append(label)
        builtAxisLimits.append(axisLimit)
        onBuild?(label)
    }
}

extension NewsTimelineTests {
    private func makeSuggestion(
        _ label: String,
        exists: Bool = false,
        hasUpdates: Bool = true
    ) -> NewsTimelineSuggestion {
        NewsTimelineSuggestion(
            label: label, headings: ["금융/증시"], eventCount: 50, reportCount: 68, monthCount: 8,
            dateFrom: "2026-02-22", dateTo: "2026-09-08",
            alreadyExists: exists, estimatedCalls: 9, hasUpdates: hasUpdates
        )
    }

    /// 제안은 러너에서 받아온다. 사용자가 「만들기」를 열 때만 부른다.
    func testLoadSuggestions_populatesFromGateway() async throws {
        let gateway = FakeTimelineGateway()
        gateway.suggestions = [makeSuggestion("금리/거시경제"), makeSuggestion("AI/반도체")]
        let viewModel = NewsTimelineViewModel()

        await viewModel.loadSuggestions(gateway: gateway, dataBasePath: base.path)

        XCTAssertEqual(viewModel.suggestions.map(\.label), ["금리/거시경제", "AI/반도체"])
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 제안 목록에서 각 주제의 갱신 필요 여부(hasUpdates)가 정상적으로 유지된다.
    func testLoadSuggestions_preservesHasUpdatesFlag() async throws {
        let gateway = FakeTimelineGateway()
        gateway.suggestions = [
            makeSuggestion("금리/거시경제", exists: true, hasUpdates: false),
            makeSuggestion("AI/반도체", exists: true, hasUpdates: true),
        ]
        let viewModel = NewsTimelineViewModel()

        await viewModel.loadSuggestions(gateway: gateway, dataBasePath: base.path)

        XCTAssertFalse(viewModel.suggestions[0].hasUpdates)
        XCTAssertTrue(viewModel.suggestions[1].hasUpdates)
    }

    /// 제안을 못 받아도 화면이 죽지 않고 사유를 보여준다.
    func testLoadSuggestions_failure_surfacesMessageAndClearsList() async throws {
        let gateway = FakeTimelineGateway()
        gateway.suggestError = NewsTimelineError.runnerNotFound
        let viewModel = NewsTimelineViewModel()

        await viewModel.loadSuggestions(gateway: gateway, dataBasePath: base.path)

        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// **사용자가 고른 주제만** 만들어진다. 만든 뒤 바로 보여준다.
    func testBuild_createsOnlyChosenTopicAndSelectsIt() async throws {
        let gateway = FakeTimelineGateway()
        gateway.onBuild = { [self] label in
            // 러너가 상태 파일을 쓴 상황을 재현한다.
            try? write(categoryId: "금리-거시경제", json: sampleJSON(
                categoryId: "금리-거시경제", categoryLabel: label
            ))
        }
        let viewModel = NewsTimelineViewModel()
        XCTAssertTrue(viewModel.isEmpty)

        await viewModel.build(
            label: "금리/거시경제", axisLimit: 5,
            gateway: gateway, dataBasePath: base.path
        )

        XCTAssertEqual(gateway.builtLabels, ["금리/거시경제"], "고른 것 하나만 만들어야 한다")
        XCTAssertEqual(gateway.builtAxisLimits, [5])
        XCTAssertEqual(viewModel.selectedTimeline?.categoryLabel, "금리/거시경제")
        XCTAssertNil(viewModel.buildingLabel, "끝나면 진행 상태가 풀려야 한다")
    }

    /// 생성이 실패해도 예외가 화면 밖으로 새지 않는다.
    func testBuild_failure_surfacesMessageAndStopsProgress() async throws {
        let gateway = FakeTimelineGateway()
        gateway.buildError = NewsTimelineError.runnerFailed(code: 2, message: "러너가 죽었다")
        let viewModel = NewsTimelineViewModel()

        await viewModel.build(
            label: "금리/거시경제", axisLimit: 3,
            gateway: gateway, dataBasePath: base.path
        )

        XCTAssertEqual(viewModel.errorMessage, "러너가 죽었다")
        XCTAssertNil(viewModel.buildingLabel)
    }

    /// 러너 출력(snake_case)이 Domain 값 타입으로 옮겨진다.
    func testSuggestionPayload_decodesSnakeCase() throws {
        let json = """
        {"suggestions": [{
          "label": "금리/거시경제",
          "headings": ["금융/증시", "거시경제"],
          "event_count": 50,
          "report_count": 68,
          "month_count": 8,
          "date_from": "2026-02-22",
          "date_to": "2026-09-08",
          "already_exists": true,
          "estimated_calls": 9
        }]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let payload = try decoder.decode(
            SuggestionPayload.self, from: Data(json.utf8)
        )

        let item = try XCTUnwrap(payload.suggestions.first).toDomain
        XCTAssertEqual(item.label, "금리/거시경제")
        XCTAssertEqual(item.eventCount, 50)
        XCTAssertEqual(item.reportCount, 68)
        XCTAssertTrue(item.alreadyExists)
        XCTAssertEqual(item.estimatedCalls, 9)
        XCTAssertEqual(
            item.summaryLine,
            "2026-02-22 ~ 2026-09-08 · 리포트 68편 · 50개 시점 · 8개월"
        )
    }

    /// 타임라인 러너는 리포트 러너의 «형제 파일» 이어야 한다 — 갈라지면 임포트가 깨진다.
    func testTimelineRunnerPath_resolvesSiblingOfReportRunner() throws {
        let directory = base.appendingPathComponent("runner", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reportRunner = directory.appendingPathComponent("runner.py")
        try "".write(to: reportRunner, atomically: true, encoding: .utf8)

        XCTAssertNil(
            NewsTimelineService.timelineRunnerPath(reportRunnerPath: reportRunner.path),
            "형제 파일이 없으면 nil 이어야 한다"
        )

        let timelineRunner = directory.appendingPathComponent("timeline_runner.py")
        try "".write(to: timelineRunner, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            NewsTimelineService.timelineRunnerPath(reportRunnerPath: reportRunner.path),
            timelineRunner.path
        )
    }
}

// MARK: - provider / effort 결정

extension NewsTimelineTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "news-timeline-\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    /// 기본은 리포트 설정 상속이다 — 설정을 두 벌로 늘리지 않는다.
    func testProviderPlan_inheritsReportProviderByDefault() throws {
        let defaults = try makeDefaults()
        defaults.set("ollama", forKey: Constants.NewsStorageKey.selectedProvider)
        defaults.set("qwen3:14b", forKey: Constants.NewsStorageKey.ollamaModel)

        let plan = NewsTimelineService(defaults: defaults).providerPlan()

        XCTAssertEqual(plan.provider, "ollama")
        XCTAssertEqual(plan.options?.model, "qwen3:14b")
    }

    /// 갈라 두면 타임라인만 다른 provider 를 쓴다.
    func testProviderPlan_explicitProvider_overridesReport() throws {
        let defaults = try makeDefaults()
        defaults.set("antigravity", forKey: Constants.NewsStorageKey.selectedProvider)
        defaults.set("ollama", forKey: Constants.NewsStorageKey.timelineProvider)
        defaults.set("qwen3.8:latest", forKey: Constants.NewsStorageKey.timelineOllamaModel)

        let plan = NewsTimelineService(defaults: defaults).providerPlan()

        XCTAssertEqual(plan.provider, "ollama")
        XCTAssertEqual(plan.options?.model, "qwen3.8:latest")
    }

    /// **effort 는 리포트 값을 물려받지 않는다.**
    ///
    /// 리포트는 기사마다 수십 회를 불러 `low` 가 기본이지만, 타임라인은 월별 1회 +
    /// 개요 1회뿐이라 한 단계 높여도 총액이 작다. 물려받으면 종합 품질만 손해다.
    func testProviderPlan_antigravityEffort_usesSynthesisDefaultNotReportValue() throws {
        let defaults = try makeDefaults()
        defaults.set("antigravity", forKey: Constants.NewsStorageKey.selectedProvider)
        defaults.set("low", forKey: Constants.NewsStorageKey.antigravityEffort)

        let plan = NewsTimelineService(defaults: defaults).providerPlan()

        XCTAssertEqual(plan.provider, "antigravity")
        XCTAssertEqual(plan.options?.effort, Constants.defaultNewsTimelineAntigravityEffort)
        XCTAssertNotEqual(plan.options?.effort, "low", "리포트의 low 를 그대로 쓰면 안 된다")
    }

    /// 사용자가 정한 값이 있으면 그것이 이긴다.
    func testProviderPlan_explicitTimelineEffort_wins() throws {
        let defaults = try makeDefaults()
        defaults.set("antigravity", forKey: Constants.NewsStorageKey.selectedProvider)
        defaults.set("high", forKey: Constants.NewsStorageKey.timelineAntigravityEffort)

        let plan = NewsTimelineService(defaults: defaults).providerPlan()

        XCTAssertEqual(plan.options?.effort, "high")
        XCTAssertEqual(plan.displayName, "antigravity · high")
    }
}
