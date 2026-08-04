import Foundation
import SwiftData

/// 호로롱이가 집중 넛지를 띄운 기록 한 건.
///
/// 몰입도는 세션에서 다시 계산할 수 있지만 "그때 잔소리를 들었는가" 는 그 순간에만 알 수 있다.
/// 기준을 바꿔가며 잔소리가 줄고 있는지 보려면 발동 당시의 기준선까지 함께 남겨야 한다.
@Model
final class FocusNudgeEvent {
    var id: UUID
    var firedAt: Date
    /// 집중 세션의 카테고리. 세션이 지워져도 추이는 남아야 하므로 값을 복사해 둔다.
    var category: String
    /// 발동 시점의 몰입도(0...1).
    var score: Double
    /// 그때 적용된 기준선(0...1).
    var threshold: Double
    var schemaVersion: Int

    init(
        firedAt: Date = Date(),
        category: String,
        score: Double,
        threshold: Double
    ) {
        self.id = UUID()
        self.firedAt = firedAt
        self.category = category
        self.score = score
        self.threshold = threshold
        self.schemaVersion = 1
    }
}
