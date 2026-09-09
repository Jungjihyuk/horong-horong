import XCTest
@testable import 호롱호롱

/// 과거 실행 이력으로 다음 실행의 소모량을 추정하는 규칙.
///
/// 핵심은 "설정이 달랐던 과거 실행을 현재 설정으로 환산"하는 것이다. 호출 수는
/// 다루는 아이템 수에 비례하므로 호출당 단가를 뽑아 되곱한다.
final class NewsUsageEstimatorTests: XCTestCase {

    // 시나리오 1. 요금제 정책이 없는 미지원 provider는 이력이 없으면 사용률이 비어 있다.
    func testEstimate_noHistory_unsupportedProvider_returnsColdStartWithoutPercent() {
        // Given: 실행 이력이 전혀 없다.

        // When: 아이템 20개 기준으로 추정한다.
        let estimate = NewsUsageEstimator.estimate(
            provider: "unsupported_provider",
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

    // 시나리오 1-1. 구독 요금제가 지원되는 provider(claude, codex, antigravity)는 이력이 없어도 5시간 한도 %를 추정한다.
    func testEstimate_subscriptionProvider_noHistory_calculatesColdStartPercentRange() throws {
        for provider in ["claude", "codex", "antigravity"] {
            let estimate = NewsUsageEstimator.estimate(
                provider: provider,
                plannedItems: 10,
                jobs: []
            )

            XCTAssertEqual(estimate.confidence, .coldStart)
            XCTAssertEqual(estimate.sampleCount, 0)
            XCTAssertEqual(estimate.primaryWindowMinutes, 300)
            let percentRange = try XCTUnwrap(estimate.primaryPercentRange, "provider \(provider)는 퍼센트 범위가 있어야 한다")
            XCTAssertGreaterThan(percentRange.lowerBound, 0.0)
            XCTAssertLessThan(percentRange.lowerBound, percentRange.upperBound)
        }
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
        // 소모량을 보고하지 않으면 `usage` 자체가 없다.
        let job = makeRun(provider: "antigravity", usage: nil)

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
        let jobs = (0..<3).map { _ in
            makeRun(
                provider: "codex",
                usage: NewsJobUsage(
                    callCount: 20,
                    inputTokens: 8_000,
                    outputTokens: 2_000,
                    totalCostUSD: 0.5,
                    plannedItems: 10,
                    primaryPercentDelta: 4.0,
                    primaryWindowMinutes: 300,
                    secondaryPercentDelta: nil,
                    secondaryWindowMinutes: nil,
                    planType: nil
                )
            )
        }

        // When: 같은 설정으로 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "codex", plannedItems: 10, jobs: jobs)

        // Then: 4% 부근의 범위와 창 길이가 함께 나온다.
        let percentRange = try XCTUnwrap(estimate.primaryPercentRange)
        XCTAssertTrue(percentRange.contains(4.0), "예상 차감량 범위: \(percentRange)")
        XCTAssertEqual(estimate.primaryWindowMinutes, 300)
    }

    // 시나리오 7-1. 과거 실행에 primaryPercentDelta가 없던 Claude 실행도 정책을 통해 %를 복원하여 추정한다.
    func testEstimate_claudeWithoutPercentDelta_recoversPercentFromPolicy() throws {
        // Given: 과거 실행 3건에 delta가 nil이지만 토큰(15,000)과 비용($0.20)이 있다.
        let jobs = (0..<3).map { _ in
            makeRun(
                provider: "claude",
                usage: NewsJobUsage(
                    callCount: 20,
                    inputTokens: 12_000,
                    outputTokens: 3_000,
                    totalCostUSD: 0.20,
                    plannedItems: 10,
                    primaryPercentDelta: nil, // 과거 기록은 nil
                    primaryWindowMinutes: nil
                )
            )
        }

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 정책에 따라 약 2.0% ($0.20 / $0.10) 부근의 % 범위가 산출된다.
        let percentRange = try XCTUnwrap(estimate.primaryPercentRange)
        XCTAssertTrue(percentRange.contains(2.0), "예상 차감량: \(percentRange)")
        XCTAssertEqual(estimate.primaryWindowMinutes, 300)
    }

    // 시나리오 7-2. 과거 실행에 primaryPercentDelta가 0.0으로 찍힌 Codex 실행도 토큰 수로부터 %를 복원한다.
    func testEstimate_codexZeroPercentDelta_recoversPercentFromTokens() throws {
        // Given: 과거 실행 3건에 delta가 0.0으로 잘못 기록되었지만 250,000 토큰이 사용되었다.
        let jobs = (0..<3).map { _ in
            makeRun(
                provider: "codex",
                usage: NewsJobUsage(
                    callCount: 20,
                    inputTokens: 200_000,
                    outputTokens: 50_000,
                    plannedItems: 10,
                    primaryPercentDelta: 0.0, // 더미 0.0
                    primaryWindowMinutes: 300
                )
            )
        }

        // When: 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "codex", plannedItems: 10, jobs: jobs)

        // Then: 250,000 토큰 / 250,000 = 1.0% 부근의 % 범위가 산출된다.
        let percentRange = try XCTUnwrap(estimate.primaryPercentRange)
        XCTAssertTrue(percentRange.contains(1.0), "예상 차감량: \(percentRange)")
        XCTAssertEqual(estimate.primaryWindowMinutes, 300)
    }

    // 시나리오 7-3. 실제 사용량 기준 Claude가 Codex보다 높은 한도 소모율(%)을 산출한다.
    func testEstimate_claudeConsumesMoreThanCodex() throws {
        // Given: Claude ($5.00 비용 소모) vs Codex (50만 토큰 소모)
        let claudeJobs = (0..<3).map { _ in
            makeRun(
                provider: "claude",
                usage: NewsJobUsage(
                    callCount: 25,
                    inputTokens: 10_000,
                    outputTokens: 5_000,
                    totalCostUSD: 5.00,
                    plannedItems: 10
                )
            )
        }
        let codexJobs = (0..<3).map { _ in
            makeRun(
                provider: "codex",
                usage: NewsJobUsage(
                    callCount: 25,
                    inputTokens: 400_000,
                    outputTokens: 100_000,
                    plannedItems: 10
                )
            )
        }

        // When: 둘 다 동일한 아이템 수(10개)로 추정한다.
        let claudeEst = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: claudeJobs)
        let codexEst = NewsUsageEstimator.estimate(provider: "codex", plannedItems: 10, jobs: codexJobs)

        // Then: Claude($5.00 -> 50%)가 Codex(50만 토큰 -> 2%)보다 훨씬 높은 차감율을 돌려준다.
        let claudeRange = try XCTUnwrap(claudeEst.primaryPercentRange)
        let codexRange = try XCTUnwrap(codexEst.primaryPercentRange)

        XCTAssertGreaterThan(claudeRange.lowerBound, codexRange.upperBound, "Claude가 Codex보다 한도 소모가 커야 한다")
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

    // 시나리오 9. 캐시 토큰(적중/생성)이 있으면 총 토큰 수에 포함하여 추정한다.
    func testEstimate_withCacheTokens_includesCacheInTotalTokens() {
        // Given: 인풋 3,000 + 아웃풋 2,000 + 캐시 히트 4,000 + 캐시 라이트 1,000 = 총 10,000 토큰인 실행 3건.
        let jobs = (0..<3).map { _ in
            makeRun(
                provider: "claude",
                usage: NewsJobUsage(
                    callCount: 20,
                    inputTokens: 3_000,
                    outputTokens: 2_000,
                    cacheHitTokens: 4_000,
                    cacheWriteTokens: 1_000,
                    totalCostUSD: 0.5,
                    plannedItems: 10
                )
            )
        }

        // When: 같은 설정으로 추정한다.
        let estimate = NewsUsageEstimator.estimate(provider: "claude", plannedItems: 10, jobs: jobs)

        // Then: 5,000 토큰이 아니라 캐시를 포함한 10,000 토큰 기준으로 보정된다.
        XCTAssertEqual(estimate.sampleCount, 3)
        XCTAssertEqual(estimate.confidence, .calibrated)
        XCTAssertTrue(estimate.tokenRange.contains(10_000), "예상 토큰 범위가 캐시를 포함해야 한다: \(estimate.tokenRange)")
    }

    // 시나리오 10. NewsJobUsage의 totalTokens는 캐시 적중/생성을 모두 합산한다.
    func testNewsJobUsage_totalTokens_sumsInputOutputAndCache() {
        let usage = NewsJobUsage(
            callCount: 1,
            inputTokens: 1_000,
            outputTokens: 200,
            cacheHitTokens: 300,
            cacheWriteTokens: 100
        )
        XCTAssertEqual(usage.totalTokens, 1_600)
    }

    // MARK: - Helpers

    /// **`@Model` 을 만들지 않는다.** 추정은 순수 함수라 값 타입만 있으면 된다.
    private func makeJob(
        provider: String,
        plannedItems: Int,
        calls: Int,
        input: Int,
        output: Int
    ) -> NewsJobRun {
        makeRun(
            provider: provider,
            usage: NewsJobUsage(
                callCount: calls,
                inputTokens: input,
                outputTokens: output,
                totalCostUSD: 0.5,
                plannedItems: plannedItems,
                primaryPercentDelta: nil,
                primaryWindowMinutes: nil,
                secondaryPercentDelta: nil,
                secondaryWindowMinutes: nil,
                planType: nil
            )
        )
    }

    private func makeRun(provider: String, usage: NewsJobUsage?) -> NewsJobRun {
        NewsJobRun(
            jobId: UUID().uuidString,
            status: "success",
            provider: provider,
            requestedAt: Date(),
            startedAt: nil,
            endedAt: nil,
            errorCode: nil,
            errorMessage: nil,
            logPath: nil,
            usage: usage
        )
    }
}
