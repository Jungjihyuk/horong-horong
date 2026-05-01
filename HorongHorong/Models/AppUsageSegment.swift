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
    /// 사용자가 수동으로 추가/편집한 세그먼트 여부. 자동 추적 기록과 구분하기 위한 표시.
    var isManual: Bool = false

    init(appName: String, bundleIdentifier: String, category: String, startTime: Date, endTime: Date, isManual: Bool = false) {
        self.id = UUID()
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
        self.isManual = isManual
    }

    var durationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
}
