import Foundation
import SwiftData

@MainActor
enum CategoryBehaviorConditionSetStore {
    @discardableResult
    static func upsert(
        category: String,
        maximumAppSwitchesPerAttributedTenMinutes: Double?,
        maximumCategorySwitchesPerAttributedTenMinutes: Double?,
        minimumLongestContinuousAppCategoryRatio: Double?,
        modelContext: ModelContext
    ) throws -> CategoryBehaviorConditionSet? {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else {
            throw CategoryBehaviorConditionSetValidationError.emptyCategory
        }
        try validateSwitchLimit(maximumAppSwitchesPerAttributedTenMinutes)
        try validateSwitchLimit(maximumCategorySwitchesPerAttributedTenMinutes)
        if let ratio = minimumLongestContinuousAppCategoryRatio,
           !ratio.isFinite || !(0...1).contains(ratio) {
            throw CategoryBehaviorConditionSetValidationError.invalidContinuousRatio
        }
        let normalizedMaximumAppSwitches = normalizedSwitchLimit(
            maximumAppSwitchesPerAttributedTenMinutes
        )
        let normalizedMaximumCategorySwitches = normalizedSwitchLimit(
            maximumCategorySwitchesPerAttributedTenMinutes
        )
        let normalizedMinimumContinuousRatio = normalizedContinuousRatio(
            minimumLongestContinuousAppCategoryRatio
        )
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }

        do {
            let existing = try conditionSets(
                category: normalizedCategory,
                modelContext: modelContext
            )
            guard normalizedMaximumAppSwitches != nil
                    || normalizedMaximumCategorySwitches != nil
                    || normalizedMinimumContinuousRatio != nil else {
                for conditionSet in existing {
                    modelContext.delete(conditionSet)
                }
                try modelContext.save()
                return nil
            }

            let conditionSet: CategoryBehaviorConditionSet
            if let first = existing.first {
                conditionSet = first
                for duplicate in existing.dropFirst() {
                    modelContext.delete(duplicate)
                }
                conditionSet.update(
                    maximumAppSwitchesPerAttributedTenMinutes:
                        normalizedMaximumAppSwitches,
                    maximumCategorySwitchesPerAttributedTenMinutes:
                        normalizedMaximumCategorySwitches,
                    minimumLongestContinuousAppCategoryRatio:
                        normalizedMinimumContinuousRatio
                )
            } else {
                conditionSet = CategoryBehaviorConditionSet(
                    category: normalizedCategory,
                    maximumAppSwitchesPerAttributedTenMinutes:
                        normalizedMaximumAppSwitches,
                    maximumCategorySwitchesPerAttributedTenMinutes:
                        normalizedMaximumCategorySwitches,
                    minimumLongestContinuousAppCategoryRatio:
                        normalizedMinimumContinuousRatio
                )
                modelContext.insert(conditionSet)
            }
            try modelContext.save()
            return conditionSet
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func delete(
        category: String,
        modelContext: ModelContext
    ) throws {
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }
        do {
            try prepareCategoryDeletion(category: category, modelContext: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func prepareCategoryRename(
        from oldCategory: String,
        to newCategory: String,
        modelContext: ModelContext
    ) throws {
        let oldName = oldCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !newName.isEmpty, oldName != newName else { return }

        let source = try conditionSets(category: oldName, modelContext: modelContext)
        guard let firstSource = source.first else { return }
        for duplicate in source.dropFirst() {
            modelContext.delete(duplicate)
        }
        for target in try conditionSets(category: newName, modelContext: modelContext) {
            modelContext.delete(target)
        }
        firstSource.category = newName
        firstSource.updatedAt = Date()
    }

    static func prepareCategoryDeletion(
        category: String,
        modelContext: ModelContext
    ) throws {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else { return }
        for conditionSet in try conditionSets(
            category: normalizedCategory,
            modelContext: modelContext
        ) {
            modelContext.delete(conditionSet)
        }
    }

    private static func validateSwitchLimit(_ value: Double?) throws {
        if let value, !value.isFinite || value < 0 {
            throw CategoryBehaviorConditionSetValidationError.invalidSwitchLimit
        }
    }

    private static func normalizedSwitchLimit(_ value: Double?) -> Double? {
        value.map { ($0 * 10).rounded() / 10 }
    }

    private static func normalizedContinuousRatio(_ value: Double?) -> Double? {
        value.map { ($0 * 100).rounded() / 100 }
    }

    private static func conditionSets(
        category: String,
        modelContext: ModelContext
    ) throws -> [CategoryBehaviorConditionSet] {
        let targetCategory = category
        return try modelContext.fetch(
            FetchDescriptor<CategoryBehaviorConditionSet>(
                predicate: #Predicate { $0.category == targetCategory },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }
}
