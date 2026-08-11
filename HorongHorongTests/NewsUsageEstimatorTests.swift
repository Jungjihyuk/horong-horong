import XCTest
@testable import 호롱호롱

/// 과거 실행 이력으로 다음 실행의 소모량을 추정하는 규칙.
///
/// 핵심은 "설정이 달랐던 과거 실행을 현재 설정으로 환산"하는 것이다. 호출 수는
/// 다루는 아이템 수에 비례하므로 호출당 단가를 뽑아 되곱한다.
final class NewsUsageEstimatorTests: XCTestCase {

    // 시나리오 1. 이력이 없으면 초기 추정치를 넓은 범위로 돌려준다.
    func testEstimate_noHistory_returnsColdStartRange() {
        // Given: 실행 이력이 전혀 없다.

        // When: 아이템 20개 기준으로 추정한다.
        let estimate = NewsUsageEstimator.estimate(
            provider: "codex",
            plannedItems: 20,
            jobs: []
        )

        // Then: 초기 추정으로 표시되고, 알 수 없는 비용/사용률은 비어 있다.
        XCTAssertEqual(estimate.confidence, .coldStart)
        XCTAssertEqual(estimate.sampleCount, 0)
        XCTAssertNil(estimate.costRange)
        XCTAssertNil(estimate.primaryPercentRange)
        XCTAssertLessThan(estimate.tokenRange.lowerBound, estimate.tokenRange.upperBound)
    }

    // 시나리오 2. 설정이 2배가 되면 예상 소모량도 2배가 된다.
    func testEstimate_doubledPlannedItems_scalesProportionally() {
        // Given: 아이템 10개를 20회 호출로 처리한 실행 이력 3건.
        let jobs = (0..<3).map { _ in
            makeJob(provider: "claude", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)
        }

        // When: 같은 설정과 2배 설정으로 각각 추정한다.
        let base = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)
        let doubled = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 20, jobs: jobs)

        // Then: 호출 수와 토큰이 정확히 2배가 된다.
        XCTAssertEqual(doubled.callRange.lowerBound, base.callRange.lowerBound * 2)
        XCTAssertEqual(doubled.tokenRange.upperBound, base.tokenRange.upperBound * 2)
        XCTAssertEqual(base.confidence, .calibrated)
    }

    // 시나리오 3. 이력이 부족하면 보정하되 범위를 더 넓게 잡는다.
    func testEstimate_fewSamples_widensRangeAndFlagsColdStart() {
        // Given: 실행 이력이 1건뿐이다.
        let jobs = [makeJob(provider: "claude", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)]

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 값은 보정되지만 신뢰도는 낮게 표시된다.
        XCTAssertEqual(estimate.sampleCount, 1)
        XCTAssertEqual(estimate.confidence, .coldStart)
        let width = estimate.tokenRange.upperBound - estimate.tokenRange.lowerBound
        XCTAssertGreaterThan(width, 10_000, "표본이 적으면 범위가 넓어야 한다")
    }

    // 시나리오 4. 다른 provider의 이력은 섞이지 않는다.
    func testEstimate_otherProviderHistory_isIgnored() {
        // Given: codex 이력만 3건 있다.
        let jobs = (0..<3).map { _ in
            makeJob(provider: "codex", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)
        }

        // When: claude로 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 쓸 수 있는 표본이 없어 초기 추정으로 떨어진다.
        XCTAssertEqual(estimate.sampleCount, 0)
        XCTAssertEqual(estimate.confidence, .coldStart)
    }

    // 시나리오 5. 소모량이 기록되지 않은 실행은 표본에서 제외한다.
    func testEstimate_jobsWithoutUsage_areExcluded() {
        // Given: 소모량을 보고하지 않는 provider로 돌린 실행만 있다.
        let job = NewsJob(jobId: "job-1", provider: "antigravity")
        job.usagePlannedItems = 10

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(
            provider: "antigravity",
            plannedItems: 10,
            jobs: [job]
        )

        // Then: 표본으로 쓰지 않는다.
        XCTAssertEqual(estimate.sampleCount, 0)
    }

    // 시나리오 6. 실패로 조기 종료된 실행이 섞여도 중앙값이라 흔들리지 않는다.
    func testEstimate_outlierRun_doesNotSkewMedian() {
        // Given: 정상 실행 3건과, 1회 호출만에 끝난 실패 실행 1건.
        var jobs = (0..<3).map { _ in
            makeJob(provider: "claude", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)
        }
        jobs.append(makeJob(provider: "claude", plannedItems: 10, calls: 1, input: 100, output: 10))

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 정상 실행 기준(호출 20회)에서 크게 벗어나지 않는다.
        XCTAssertTrue(
            estimate.callRange.contains(20),
            "이상치에 끌려가지 않아야 한다: \(estimate.callRange)"
        )
    }

    // 시나리오 7. 사용률을 보고한 이력이 있으면 차감 예정 %를 계산한다.
    func testEstimate_withRateLimitHistory_predictsPercentRange() throws {
        // Given: 20회 호출로 사용률 4%를 쓴 실행 3건.
        let jobs = (0..<3).map { _ -> NewsJob in
            let job = makeJob(provider: "codex", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)
            job.usagePrimaryPercentDelta = 4.0
            job.usagePrimaryWindowMinutes = 300
            return job
        }

        // When: 같은 설정으로 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "codex", plannedItems: 10, jobs: jobs)

        // Then: 4% 부근의 범위와 창 길이가 함께 나온다.
        let percentRange = try XCTUnwrap(estimate.primaryPercentRange)
        XCTAssertTrue(percentRange.contains(4.0), "예상 차감량 범위: \(percentRange)")
        XCTAssertEqual(estimate.primaryWindowMinutes, 300)
    }

    // 시나리오 8. 보정에는 최근 실행만 쓴다.
    func testEstimate_moreHistoryThanWindow_usesOnlyRecentRuns() {
        // Given: 최근 실행 10건은 호출 20회, 그 이전 10건은 호출 200회다.
        var jobs = (0..<NewsUsageEstimator.historyWindow).map { _ in
            makeJob(provider: "claude", plannedItems: 10, calls: 20, input: 8_000, output: 2_000)
        }
        jobs += (0..<10).map { _ in
            makeJob(provider: "claude", plannedItems: 10, calls: 200, input: 80_000, output: 20_000)
        }

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 오래된 실행에 끌려가지 않는다.
        XCTAssertTrue(
            estimate.callRange.contains(20),
            "최근 이력만 반영해야 한다: \(estimate.callRange)"
        )
    }

    // MARK: - Helpers

    private func makeJob(
        provider: String,
        plannedItems: Int,
        calls: Int,
        input: Int,
        output: Int
    ) -> NewsJob {
        let job = NewsJob(jobId: UUID().uuidString, provider: provider)
        job.status = "success"
        job.usagePlannedItems = plannedItems
        job.usageCallCount = calls
        job.usageInputTokens = input
        job.usageOutputTokens = output
        job.usageTotalCostUSD = 0.5
        return job
    }
}
