import Foundation
import SwiftData

@Model
final class CategoryBehaviorConditionSet {
    var id: UUID
    @Attribute(.unique)
    var category: String
    var maximumAppSwitchesPerAttributedTenMinutes: Double?
    var maximumCategorySwitchesPerAttributedTenMinutes: Double?
    var minimumLongestContinuousAppCategoryRatio: Double?
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int

    init(
        category: String,
        maximumAppSwitchesPerAttributedTenMinutes: Double? = nil,
        maximumCategorySwitchesPerAttributedTenMinutes: Double? = nil,
        minimumLongestContinuousAppCategoryRatio: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maximumAppSwitchesPerAttributedTenMinutes =
            maximumAppSwitchesPerAttributedTenMinutes
        self.maximumCategorySwitchesPerAttributedTenMinutes =
            maximumCategorySwitchesPerAttributedTenMinutes
        self.minimumLongestContinuousAppCategoryRatio =
            minimumLongestContinuousAppCategoryRatio
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.schemaVersion = 1
    }

    var conditionCount: Int {
        [
            maximumAppSwitchesPerAttributedTenMinutes,
            maximumCategorySwitchesPerAttributedTenMinutes,
            minimumLongestContinuousAppCategoryRatio,
        ].compactMap { $0 }.count
    }

    func update(
        maximumAppSwitchesPerAttributedTenMinutes: Double?,
        maximumCategorySwitchesPerAttributedTenMinutes: Double?,
        minimumLongestContinuousAppCategoryRatio: Double?,
        updatedAt: Date = Date()
    ) {
        self.maximumAppSwitchesPerAttributedTenMinutes =
            maximumAppSwitchesPerAttributedTenMinutes
        self.maximumCategorySwitchesPerAttributedTenMinutes =
            maximumCategorySwitchesPerAttributedTenMinutes
        self.minimumLongestContinuousAppCategoryRatio =
            minimumLongestContinuousAppCategoryRatio
        self.updatedAt = updatedAt
    }
}

enum CategoryBehaviorConditionSetValidationError: LocalizedError {
    case emptyCategory
    case invalidSwitchLimit
    case invalidContinuousRatio
    case pendingChanges

    var errorDescription: String? {
        switch self {
        case .emptyCategory:
            return "카테고리를 확인해 주세요."
        case .invalidSwitchLimit:
            return "전환 기준은 0 이상의 숫자로 입력해 주세요."
        case .invalidContinuousRatio:
            return "이어진 비율은 0%에서 100% 사이로 입력해 주세요."
        case .pendingChanges:
            return "다른 변경 내용을 저장한 뒤 다시 시도해 주세요."
        }
    }
}
