import Foundation
import SwiftData

/// `NewsRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataNewsRepository: NewsRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func recentReports(limit: Int) throws -> [NewsReport] {
        var descriptor = FetchDescriptor<NewsReportIndex>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(Self.toReport)
    }

    func recentJobs(limit: Int) throws -> [NewsJobRun] {
        var descriptor = FetchDescriptor<NewsJob>(
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(Self.toRun)
    }

    func reportIdentifiers() throws -> [String] {
        var descriptor = FetchDescriptor<NewsReportIndex>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // 식별자만 쓰므로 나머지 컬럼을 실체화하지 않는다.
        descriptor.propertiesToFetch = [\.jobId]
        return try context.fetch(descriptor).map(\.jobId)
    }

    private static func toReport(_ index: NewsReportIndex) -> NewsReport {
        NewsReport(
            jobId: index.jobId,
            reportDate: index.reportDate,
            reportPath: index.reportPath,
            metaPath: index.metaPath,
            topTitle: index.topTitle,
            itemCount: index.itemCount,
            createdAt: index.createdAt
        )
    }

    private static func toRun(_ job: NewsJob) -> NewsJobRun {
        NewsJobRun(
            jobId: job.jobId,
            status: job.status,
            provider: job.provider,
            requestedAt: job.requestedAt,
            startedAt: job.startedAt,
            endedAt: job.endedAt,
            errorCode: job.errorCode,
            errorMessage: job.errorMessage,
            logPath: job.logPath,
            usage: Self.toUsage(job)
        )
    }

    /// 호출 수가 없으면 소모량 자체를 만들지 않는다 — 「호출당 얼마」로 환산할 수 없어
    /// 표본으로 못 쓰기 때문이다. 화면의 «소모량이 기록된 실행» 판정도 이걸로 통일된다.
    private static func toUsage(_ job: NewsJob) -> NewsJobUsage? {
        guard let callCount = job.usageCallCount else { return nil }
        return NewsJobUsage(
            callCount: callCount,
            inputTokens: job.usageInputTokens,
            outputTokens: job.usageOutputTokens,
            totalCostUSD: job.usageTotalCostUSD,
            plannedItems: job.usagePlannedItems,
            primaryPercentDelta: job.usagePrimaryPercentDelta,
            primaryWindowMinutes: job.usagePrimaryWindowMinutes,
            secondaryPercentDelta: job.usageSecondaryPercentDelta,
            secondaryWindowMinutes: job.usageSecondaryWindowMinutes,
            planType: job.usagePlanType
        )
    }
}
