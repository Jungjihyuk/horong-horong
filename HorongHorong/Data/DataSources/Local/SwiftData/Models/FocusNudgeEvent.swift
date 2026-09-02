import Foundation
import SwiftData

/// 호로롱이가 집중 넛지를 띄운 기록 한 건.
///
/// 화면 표시가 성공한 순간의 사실과 이유를 함께 남긴다.
@Model
final class FocusNudgeEvent {
    var id: UUID
    var firedAt: Date
    /// 집중 세션의 카테고리. 세션이 지워져도 추이는 남아야 하므로 값을 복사해 둔다.
    var category: String
    /// 과거 행은 값이 없을 수 있다. 새 행은 이 값으로 세션별 횟수를 정확히 센다.
    var focusSessionID: UUID?
    var observedFocusRatio: Double?
    var minimumFocusRatio: Double?
    var observedAppSwitches: Int?
    var maximumAppSwitches: Int?
    var policySourceRawValue: String?
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        firedAt: Date = Date(),
        category: String,
        focusSessionID: UUID? = nil,
        observedFocusRatio: Double? = nil,
        minimumFocusRatio: Double? = nil,
        observedAppSwitches: Int? = nil,
        maximumAppSwitches: Int? = nil,
        policySource: FocusNudgePolicySource? = nil
    ) {
        self.id = id
        self.firedAt = firedAt
        self.category = category
        self.focusSessionID = focusSessionID
        self.observedFocusRatio = observedFocusRatio
        self.minimumFocusRatio = minimumFocusRatio
        self.observedAppSwitches = observedAppSwitches
        self.maximumAppSwitches = maximumAppSwitches
        self.policySourceRawValue = policySource?.rawValue
        self.schemaVersion = 2
    }
}
