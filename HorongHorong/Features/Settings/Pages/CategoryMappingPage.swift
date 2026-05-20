import SwiftUI
import SwiftData

struct CategoryMappingPage: View {
    @Environment(\.modelContext) private var modelContext

    @State private var categoryRules: [AppCategoryRule] = []
    @State private var categoryStore = CategoryStore.shared
    @State private var idleThresholdStore = IdleThresholdStore.shared
    @State private var pairStore = CategoryPairStore.shared

    @State private var showAddCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryEmoji: String = "📦"

    @State private var showAddRule: Bool = false
    @State private var newBundleId: String = ""
    @State private var newAppName: String = ""
    @State private var newCategory: String = Constants.categoryName("기타")

    @State private var showAddPair: Bool = false
    @State private var newPairA: String = Constants.allCategories.first ?? Constants.categoryName("기타")
    @State private var newPairB: String = Constants.allCategories.dropFirst().first
        ?? Constants.allCategories.first
        ?? Constants.categoryName("기타")

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.category.label, subtitle: SettingsTab.category.subtitle)

            categoriesCard
            appRulesCard
            idleThresholdCard
            pairCard
        }
        .onAppear { loadRules() }
    }

    // MARK: - 카테고리 정의

    private var categoriesCard: some View {
        SettingsGroupCard("카테고리") {
            VStack(spacing: 0) {
                ForEach(categoryStore.categories) { category in
                    categoryDefinitionRow(category)
                }

                if showAddCategory {
                    addCategoryForm
                }

                HStack {
                    Button {
                        showAddCategory.toggle()
                    } label: {
                        Label("카테고리 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("이름 변경은 기존 기록·앱 규칙까지 함께 바꿉니다. 삭제 시 기록은 기타로 이동합니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func categoryDefinitionRow(_ category: CategoryDefinition) -> some View {
        SettingsRow(category.name, subtitle: category.defaultName == category.name ? nil : "기본: \(category.defaultName)") {
            TextField("이모지", text: Binding(
                get: { category.emoji },
                set: { updateCategory(oldName: category.name, newName: category.name, emoji: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(width: 56)

            TextField("이름", text: Binding(
                get: { category.name },
                set: { updateCategory(oldName: category.name, newName: $0, emoji: category.emoji) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(width: 100)
            .disabled(category.defaultName == "기타")

            if category.defaultName != category.name
                || category.emoji != (Constants.categoryEmoji[category.defaultName] ?? category.emoji) {
                Button {
                    updateCategory(
                        oldName: category.name,
                        newName: category.defaultName,
                        emoji: Constants.categoryEmoji[category.defaultName] ?? category.emoji
                    )
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("기본값으로 되돌리기")
            }

            Button(role: .destructive) {
                deleteCategory(category.name)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(categoryStore.canDelete(category.name) ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!categoryStore.canDelete(category.name))
            .help(categoryStore.canDelete(category.name) ? "삭제하고 기록을 기타로 이동" : "기타는 삭제할 수 없습니다")
        }
    }

    private var addCategoryForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("이모지", text: $newCategoryEmoji)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 56)
                TextField("카테고리 이름", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                Button("취소") {
                    showAddCategory = false
                    resetCategoryForm()
                }
                .controlSize(.small)
                Button("추가") {
                    if categoryStore.add(name: newCategoryName, emoji: newCategoryEmoji) {
                        resetCategorySelections()
                        resetCategoryForm()
                        showAddCategory = false
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveNewCategory)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - 앱 규칙

    private var appRulesCard: some View {
        SettingsGroupCard("앱 → 카테고리") {
            VStack(spacing: 0) {
                if categoryRules.isEmpty {
                    Text("등록된 앱 규칙이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(groupedCategoryRules, id: \.category) { group in
                        appRuleGroupHeader(category: group.category, count: group.rules.count)
                        ForEach(group.rules) { rule in
                            appRuleRow(rule)
                        }
                    }
                }

                if showAddRule {
                    addRuleForm
                }

                HStack {
                    Button {
                        showAddRule.toggle()
                    } label: {
                        Label("앱 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("매핑되지 않은 앱은 \"기타\"로 집계됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func appRuleGroupHeader(category: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(Constants.categoryEmoji(for: category))
            Text(category)
                .font(.caption.bold())
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func appRuleRow(_ rule: AppCategoryRule) -> some View {
        SettingsRow(
            rule.appName,
            subtitle: rule.bundleIdentifier
        ) {
            Text(rule.isUserDefined ? "사용자" : "기본")
                .font(.caption2)
                .foregroundStyle(rule.isUserDefined ? SettingsTheme.accent : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

            Picker("", selection: Binding(
                get: { rule.category },
                set: { updateRule(rule, category: $0) }
            )) {
                ForEach(Constants.allCategories, id: \.self) { cat in
                    Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                }
            }
            .labelsHidden()
            .frame(width: 112)

            if canResetRule(rule) {
                Button {
                    resetRuleToDefault(rule)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("기본 카테고리로 되돌리기")
            } else if rule.isUserDefined {
                Button(role: .destructive) {
                    deleteRule(rule)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("사용자 규칙 삭제")
            } else {
                Image(systemName: "lock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("기본 규칙은 삭제 불가, 카테고리 수정 또는 기본값 복원만 지원")
            }
        }
    }

    private var addRuleForm: some View {
        VStack(spacing: 8) {
            TextField("번들 ID (예: com.example.app)", text: $newBundleId)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            TextField("앱 이름", text: $newAppName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            HStack {
                Picker("카테고리", selection: $newCategory) {
                    ForEach(Constants.allCategories, id: \.self) { cat in
                        Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                Button("취소") {
                    showAddRule = false
                    resetRuleForm()
                }
                .controlSize(.small)
                Button("추가") {
                    upsertUserRule()
                    try? modelContext.save()
                    showAddRule = false
                    resetRuleForm()
                    loadRules()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveNewRule)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - 자리비움 임계값

    private var idleThresholdCard: some View {
        SettingsGroupCard("자리 비움 감지 임계값") {
            VStack(spacing: 0) {
                Text("입력이 N분 이상 없으면 복귀 시 \"작업 시간으로 인정할까요?\" 를 묻습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ForEach(Constants.allCategories, id: \.self) { category in
                    idleThresholdRow(for: category)
                }
            }
        }
    }

    private func idleThresholdRow(for category: String) -> some View {
        SettingsRow("\(Constants.categoryEmoji(for: category)) \(category)") {
            NumberField(
                value: Binding(
                    get: { idleThresholdStore.minutes(for: category) },
                    set: { idleThresholdStore.setMinutes($0, for: category) }
                ),
                range: 1...180,
                suffix: "분",
                width: 56
            )
            Button {
                idleThresholdStore.resetToDefault(category: category)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("기본값으로 되돌리기")
        }
    }

    // MARK: - 짝 카테고리

    private var pairCard: some View {
        SettingsGroupCard("짝 카테고리 (전환 무시)") {
            VStack(spacing: 0) {
                Text("같이 쓰는 카테고리 쌍을 등록하면 그 사이 전환은 산만 카운트에서 제외합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                if pairStore.pairs.isEmpty {
                    Text("등록된 짝이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ForEach(pairStore.pairs, id: \.self) { pair in
                        SettingsRow(
                            "\(Constants.categoryEmoji(for: pair.first)) \(pair.first)  ↔  \(Constants.categoryEmoji(for: pair.second)) \(pair.second)"
                        ) {
                            Button(role: .destructive) {
                                pairStore.remove(pair)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if showAddPair {
                    addPairForm
                }

                HStack {
                    Button {
                        showAddPair.toggle()
                    } label: {
                        Label("짝 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private var addPairForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $newPairA) {
                    ForEach(Constants.allCategories, id: \.self) { cat in
                        Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)

                Picker("", selection: $newPairB) {
                    ForEach(Constants.allCategories, id: \.self) { cat in
                        Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if newPairA == newPairB {
                Text("서로 다른 카테고리를 골라주세요")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if pairStore.contains(newPairA, newPairB) {
                Text("이미 등록된 짝입니다")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소") {
                    showAddPair = false
                }
                .controlSize(.small)
                Button("추가") {
                    pairStore.add(newPairA, newPairB)
                    showAddPair = false
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(newPairA == newPairB || pairStore.contains(newPairA, newPairB))
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Derived

    private var groupedCategoryRules: [(category: String, rules: [AppCategoryRule])] {
        let grouped = Dictionary(grouping: categoryRules) { $0.category }
        return Constants.allCategories.compactMap { category in
            guard let rules = grouped[category], !rules.isEmpty else { return nil }
            return (
                category: category,
                rules: rules.sorted {
                    if $0.appName != $1.appName { return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
                    return $0.bundleIdentifier < $1.bundleIdentifier
                }
            )
        }
    }

    private var canSaveNewCategory: Bool {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !Constants.allCategories.contains(name)
    }

    private var canSaveNewRule: Bool {
        !trimmedNewBundleId.isEmpty && !trimmedNewAppName.isEmpty
    }

    private var trimmedNewBundleId: String {
        newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewAppName: String {
        newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Mutations

    private func updateCategory(oldName: String, newName: String, emoji: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard trimmedName == oldName || !Constants.allCategories.contains(trimmedName) else { return }

        let defaultName = Constants.defaultName(forCategory: oldName)
        if defaultName == "기타", trimmedName != oldName {
            return
        }

        guard categoryStore.update(oldName: oldName, newName: trimmedName, emoji: emoji) else { return }
        if trimmedName != oldName {
            migrateCategory(from: oldName, to: trimmedName)
        }
        resetCategorySelections()
        loadRules()
    }

    private func deleteCategory(_ category: String) {
        guard categoryStore.canDelete(category) else { return }
        let fallback = Constants.categoryName("기타")
        migrateCategory(from: category, to: fallback)
        categoryStore.delete(name: category)
        pairStore.removeCategory(category)
        resetCategorySelections()
        loadRules()
    }

    private func migrateCategory(from oldName: String, to newName: String) {
        guard oldName != newName else { return }

        let oldCategory = oldName
        let newCategory = newName

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for segment in (try? modelContext.fetch(segmentDescriptor)) ?? [] {
            segment.category = newCategory
        }

        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for record in (try? modelContext.fetch(recordDescriptor)) ?? [] {
            record.category = newCategory
        }

        let focusDescriptor = FetchDescriptor<FocusSession>()
        for session in (try? modelContext.fetch(focusDescriptor)) ?? [] where session.category == oldCategory {
            session.category = newCategory
        }

        let ruleDescriptor = FetchDescriptor<AppCategoryRule>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        for rule in (try? modelContext.fetch(ruleDescriptor)) ?? [] {
            rule.category = newCategory
            if let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier),
               defaultRule.category == newCategory {
                rule.isUserDefined = false
                CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
            } else {
                rule.isUserDefined = true
                CategoryManager.shared.setUserRule(bundleIdentifier: rule.bundleIdentifier, category: newCategory)
            }
        }

        if UserDefaults.standard.string(forKey: Constants.AppStorageKey.selectedFocusCategory) == oldCategory {
            UserDefaults.standard.set(newCategory, forKey: Constants.AppStorageKey.selectedFocusCategory)
        }

        let oldIdleKey = IdleThresholdStore.userDefaultsKey(for: oldCategory)
        let newIdleKey = IdleThresholdStore.userDefaultsKey(for: newCategory)
        let oldIdleValue = UserDefaults.standard.integer(forKey: oldIdleKey)
        if oldIdleValue > 0 {
            UserDefaults.standard.set(oldIdleValue, forKey: newIdleKey)
            UserDefaults.standard.removeObject(forKey: oldIdleKey)
        }

        pairStore.renameCategory(from: oldCategory, to: newCategory)
        try? modelContext.save()
        CategoryManager.shared.loadUserRules(from: modelContext)
    }

    private func resetCategorySelections() {
        let categories = Constants.allCategories
        if !categories.contains(newCategory) {
            newCategory = categories.first ?? Constants.categoryName("기타")
        }
        if !categories.contains(newPairA) {
            newPairA = categories.first ?? Constants.categoryName("기타")
        }
        if !categories.contains(newPairB) {
            newPairB = categories.dropFirst().first ?? categories.first ?? Constants.categoryName("기타")
        }
    }

    private func resetCategoryForm() {
        newCategoryName = ""
        newCategoryEmoji = "📦"
    }

    private func resetRuleForm() {
        newBundleId = ""
        newAppName = ""
        newCategory = Constants.categoryName("기타")
    }

    private func loadRules() {
        insertMissingDefaultRules()
        var descriptor = FetchDescriptor<AppCategoryRule>()
        descriptor.sortBy = [
            SortDescriptor(\AppCategoryRule.category),
            SortDescriptor(\AppCategoryRule.appName),
        ]
        categoryRules = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func insertMissingDefaultRules() {
        let descriptor = FetchDescriptor<AppCategoryRule>()
        let existingRules = (try? modelContext.fetch(descriptor)) ?? []
        let existingBundleIds = Set(existingRules.map(\.bundleIdentifier))

        for rule in Constants.defaultCategoryRules where !existingBundleIds.contains(rule.bundleId) {
            modelContext.insert(AppCategoryRule(
                bundleIdentifier: rule.bundleId,
                appName: rule.appName,
                category: rule.category,
                isUserDefined: false
            ))
        }
        try? modelContext.save()
    }

    private func upsertUserRule() {
        let bundleId = trimmedNewBundleId
        let appName = trimmedNewAppName
        guard !bundleId.isEmpty, !appName.isEmpty else { return }

        if let existing = categoryRules.first(where: { $0.bundleIdentifier == bundleId }) {
            existing.appName = appName
            updateRule(existing, category: newCategory)
        } else {
            let rule = AppCategoryRule(
                bundleIdentifier: bundleId,
                appName: appName,
                category: newCategory,
                isUserDefined: true
            )
            modelContext.insert(rule)
            CategoryManager.shared.setUserRule(bundleIdentifier: bundleId, category: newCategory)
        }
    }

    private func updateRule(_ rule: AppCategoryRule, category: String) {
        rule.category = category
        if let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier),
           defaultRule.category == category {
            rule.isUserDefined = false
            CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
        } else {
            rule.isUserDefined = true
            CategoryManager.shared.setUserRule(bundleIdentifier: rule.bundleIdentifier, category: category)
        }
        try? modelContext.save()
        loadRules()
    }

    private func canResetRule(_ rule: AppCategoryRule) -> Bool {
        guard let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier) else { return false }
        return rule.isUserDefined || rule.category != defaultRule.category
    }

    private func resetRuleToDefault(_ rule: AppCategoryRule) {
        guard let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier) else { return }
        rule.appName = defaultRule.appName
        rule.category = defaultRule.category
        rule.isUserDefined = false
        CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
        try? modelContext.save()
        loadRules()
    }

    private func deleteRule(_ rule: AppCategoryRule) {
        modelContext.delete(rule)
        try? modelContext.save()
        CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
        loadRules()
    }
}
