import Foundation
import SwiftData

@Model
final class AppUsageSegment {
    var id: UUID
    var appName: String
    var bundleIdentifier: String
    var category: String
    var startTime: Date
    var endTime: Date
    /// 사용자가 처음부터 수동으로 추가한 세그먼트 여부. 자동 추적 기록과 구분하기 위한 표시.
    var isManual: Bool = false
    /// 자동 기록을 포함해 사용자가 직접 추가하거나 수정한 적이 있는지 여부.
    var isUserModified: Bool = false

    init(
        appName: String,
        bundleIdentifier: String,
        category: String,
        startTime: Date,
        endTime: Date,
        isManual: Bool = false,
        isUserModified: Bool? = nil
    ) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
        self.isManual = isManual
        self.isUserModified = isUserModified ?? isManual
    }

    var durationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
}
