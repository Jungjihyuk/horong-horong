import Foundation
import SwiftData

/// `AppUsageRepository` 의 SwiftData 구현.
///
/// **자동 저장을 끈 별도 컨텍스트를 쓴다.** 앱을 옮길 때마다 쓰기가 일어나므로,
/// 화면이 쓰는 컨텍스트와 섞으면 편집 중인 화면이 계속 흔들린다.
@MainActor
final class SwiftDataAppUsageRepository: AppUsageRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
    }

    /// 이미 만들어 둔 컨텍스트를 쓸 때(테스트·다른 저장소와 같은 트랜잭션).
    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - 분류 규칙

    func userDefinedRules() -> [AppCategoryRuleSnapshot] {
        let descriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.isUserDefined == true }
        )
        return ((try? context.fetch(descriptor)) ?? []).map {
            AppCategoryRuleSnapshot(
                bundleIdentifier: $0.bundleIdentifier,
                category: $0.category,
                isExcluded: $0.isExcluded
            )
        }
    }

    func migrateLegacyProductivityManagementCategory() {
        let legacy = Constants.legacySupportAppCategory
        let current = Constants.productivityManagementAppCategory
        var changed = false

        for rule in fetch(FetchDescriptor<AppCategoryRule>(predicate: #Predicate { $0.category == legacy })) {
            rule.category = current
            changed = true
        }
        for segment in fetch(FetchDescriptor<AppUsageSegment>(predicate: #Predicate { $0.category == legacy })) {
            segment.category = current
            changed = true
        }
        for record in fetch(FetchDescriptor<AppUsageRecord>(predicate: #Predicate { $0.category == legacy })) {
            record.category = current
            changed = true
        }

        if changed { try? context.save() }
    }

    // MARK: - 사용 시간

    func applyUsageDelta(
        bundleIdentifier: String,
        appName: String,
        category: String,
        date: Date,
        deltaSeconds: Int
    ) {
        try? AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            date: date,
            deltaSeconds: deltaSeconds,
            modelContext: context
        )
        try? context.save()
    }

    func recordSegment(
        appName: String,
        bundleIdentifier: String,
        category: String,
        from start: Date,
        to end: Date,
        minimumSeconds: TimeInterval
    ) -> Bool {
        let elapsed = end.timeIntervalSince(start)
        guard elapsed >= 0 else { return false }

        // 바로 앞 구간을 찾는다 — 같은 앱·같은 갈래로 이 구간이 시작한 시각에 끝난 것.
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate {
                $0.bundleIdentifier == bundleIdentifier &&
                $0.category == category &&
                $0.endTime == start
            },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        let previous = try? context.fetch(descriptor).first

        // 이어붙일 앞 구간이 없으면 너무 짧은 방문은 버린다.
        guard previous != nil || elapsed >= minimumSeconds else { return false }

        if let previous {
            previous.appName = appName
            previous.endTime = end
        } else {
            context.insert(AppUsageSegment(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                category: category,
                startTime: start,
                endTime: end
            ))
        }
        try? context.save()
        return true
    }

    func subtractIdleTime(
        appName: String,
        bundleIdentifier: String,
        category: String,
        from idleStart: Date,
        to idleEnd: Date,
        minimumSeconds: TimeInterval
    ) {
        guard idleEnd.timeIntervalSince(idleStart) > 0 else { return }

        // (1) 일일 총사용 시간 차감. 자정을 넘겼으면 날짜별로 나눠 뺀다.
        for slice in AppUsageDaySlicer.slices(from: idleStart, to: idleEnd) {
            try? AppUsageRecordStore.applyDelta(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                category: category,
                date: slice.date,
                deltaSeconds: -slice.durationSeconds,
                modelContext: context
            )
        }

        // (2) 타임라인 구간 보정 — 자리 비운 시간과 겹치는 것을 잘라내거나 지운다.
        let overlapping = fetch(FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < idleEnd && $0.endTime > idleStart }
        ))

        for segment in overlapping {
            let originalStart = segment.startTime
            let originalEnd = segment.endTime

            if originalStart >= idleStart && originalEnd <= idleEnd {
                // 통째로 자리 비운 시간 안 → 지운다.
                context.delete(segment)
            } else if originalStart < idleStart && originalEnd <= idleEnd {
                // 뒷부분이 걸림 → 끝을 당긴다.
                segment.endTime = idleStart
                deleteIfTooShort(segment, minimumSeconds: minimumSeconds)
            } else if originalStart >= idleStart && originalEnd > idleEnd {
                // 앞부분이 걸림 → 시작을 민다.
                segment.startTime = idleEnd
                deleteIfTooShort(segment, minimumSeconds: minimumSeconds)
            } else {
                // 한가운데가 걸림 → 앞뒤로 쪼갠다.
                split(segment, around: idleStart...idleEnd, originalEnd: originalEnd, minimumSeconds: minimumSeconds)
            }
        }

        try? context.save()
    }

    // MARK: - 내부

    private func split(
        _ segment: AppUsageSegment,
        around idle: ClosedRange<Date>,
        originalEnd: Date,
        minimumSeconds: TimeInterval
    ) {
        let frontDuration = idle.lowerBound.timeIntervalSince(segment.startTime)
        let backDuration = originalEnd.timeIntervalSince(idle.upperBound)
        let appName = segment.appName
        let bundleIdentifier = segment.bundleIdentifier
        let category = segment.category
        let isManual = segment.isManual
        // 쪼갠 조각도 «사람이 손댄 것» 으로 남긴다. 자동 보정이 덮어쓰지 않게.
        let isUserModified = segment.isUserModified || segment.isManual

        if frontDuration >= minimumSeconds {
            segment.endTime = idle.lowerBound
        } else {
            context.delete(segment)
        }

        if backDuration >= minimumSeconds {
            context.insert(AppUsageSegment(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                category: category,
                startTime: idle.upperBound,
                endTime: originalEnd,
                isManual: isManual,
                isUserModified: isUserModified
            ))
        }
    }

    private func deleteIfTooShort(_ segment: AppUsageSegment, minimumSeconds: TimeInterval) {
        guard segment.endTime.timeIntervalSince(segment.startTime) < minimumSeconds else { return }
        context.delete(segment)
    }

    private func fetch<T>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }
}
