import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CategoryMappingPage: View {
    private static let excludedRuleGroup = "__tracking_excluded__"

    private struct PendingRuleCategoryChange {
        let rule: AppCategoryRule
        let displayName: String
        let oldCategory: String
        let newCategory: String
        let replacementAppName: String?
        let closesAddRuleForm: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.AppStorageKey.unmappedAppHandling)
    private var unmappedAppHandlingRaw: String =
        Constants.defaultUnmappedAppHandling.rawValue

    @State private var categoryRules: [AppCategoryRule] = []
    @State private var websiteRules: [AppCategoryRule] = []
    @State private var unclassifiedApps: [UnclassifiedAppUsage] = []
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

    @State private var showAddWebsiteRule: Bool = false
    @State private var newWebsiteAddress: String = ""
    @State private var newWebsiteCategory: String = Constants.categoryName("기타")

    @State private var showAddPair: Bool = false
    @State private var newPairA: String = Constants.allCategories.first ?? Constants.categoryName("기타")
    @State private var newPairB: String = Constants.allCategories.dropFirst().first
        ?? Constants.allCategories.first
        ?? Constants.categoryName("기타")
    @State private var categoryMutationError: String?
    @State private var markerColorResetCategory: String?
    @State private var pendingRuleCategoryChange: PendingRuleCategoryChange?

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.category.label, subtitle: SettingsTab.category.subtitle)

            categoriesCard
            appRulesCard
            websiteRulesCard
            idleThresholdCard
            pairCard
        }
        .onAppear { loadRules() }
        .alert(
            "카테고리를 변경하지 못했어요",
            isPresented: Binding(
                get: { categoryMutationError != nil },
                set: { if !$0 { categoryMutationError = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                categoryMutationError = nil
            }
        } message: {
            Text(categoryMutationError ?? "잠시 후 다시 시도해 주세요.")
        }
        .confirmationDialog(
            "기존 기록도 변경할까요?",
            isPresented: Binding(
                get: { pendingRuleCategoryChange != nil },
                set: { if !$0 { pendingRuleCategoryChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("앞으로만 적용") {
                applyPendingRuleCategoryChange(includeExistingUsage: false)
            }
            Button("기존 기록도 변경", role: .destructive) {
                applyPendingRuleCategoryChange(includeExistingUsage: true)
            }
            Button("취소", role: .cancel) {
                pendingRuleCategoryChange = nil
            }
        } message: {
            Text(ruleCategoryChangeMessage)
        }
        .confirmationDialog(
            "세션별 색상을 초기화할까요?",
            isPresented: Binding(
                get: { markerColorResetCategory != nil },
                set: { if !$0 { markerColorResetCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("모두 기본색 사용", role: .destructive) {
                if let category = markerColorResetCategory {
                    resetSessionMarkerColors(for: category)
                }
                markerColorResetCategory = nil
            }
            Button("취소", role: .cancel) {
                markerColorResetCategory = nil
            }
        } message: {
            Text(
                "\(markerColorResetCategory ?? "이 카테고리") 세션의 개별 점 색상을 모두 지웁니다."
            )
        }
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

            Menu {
                Section("카테고리 기본색") {
                    ForEach(selectableColorOptions) { option in
                        Button {
                            setCategoryColor(option.key, for: category.name)
                        } label: {
                            Label(
                                option.name,
                                systemImage: category.colorKey == option.key
                                    ? "checkmark.circle.fill"
                                    : "circle.fill"
                            )
                        }
                    }
                }
                Divider()
                Button(role: .destructive) {
                    markerColorResetCategory = category.name
                } label: {
                    Label("세션별 색상 모두 초기화", systemImage: "arrow.uturn.backward.circle")
                }
            } label: {
                Circle()
                    .fill(CategoryColorPalette.color(for: category.colorKey))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("카테고리 색상 변경")

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
            if let message = newCategoryInputMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                SettingsRow(
                    "새 앱 처리",
                    subtitle: unmappedAppHandling.wrappedValue.subtitle
                ) {
                    Picker("", selection: unmappedAppHandling) {
                        ForEach(Constants.UnmappedAppHandling.allCases) { handling in
                            Text(handling.label).tag(handling)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                if !unclassifiedApps.isEmpty {
                    appRuleGroupHeader(
                        category: Constants.unclassifiedAppCategory,
                        count: unclassifiedApps.count
                    )
                    ForEach(unclassifiedApps) { app in
                        unclassifiedAppRow(app)
                    }
                }

                if categoryRules.isEmpty && unclassifiedApps.isEmpty {
                    Text("등록된 앱 규칙이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(groupedCategoryRules, id: \.category) { group in
                        appRuleGroupHeader(category: group.category, count: group.rules.count)
                        if Constants.isProductivityManagementCategory(group.category) {
                            productivityManagementExplanation
                        }
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
                        chooseApplication()
                    } label: {
                        Label("앱 선택…", systemImage: "plus.app")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("직접 등록한 규칙이 우선하며, 변경 사항은 앞으로 생성되는 기록부터 적용됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private var unmappedAppHandling: Binding<Constants.UnmappedAppHandling> {
        Binding(
            get: {
                Constants.UnmappedAppHandling(rawValue: unmappedAppHandlingRaw)
                    ?? Constants.defaultUnmappedAppHandling
            },
            set: { unmappedAppHandlingRaw = $0.rawValue }
        )
    }

    private var productivityManagementExplanation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("타이머·미리알림·할 일 관리처럼 작업 흐름을 관리하기 위해 잠깐 여는 앱을 등록하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("10초 미만 사용은 앱 전환에서 제외합니다. 10초 이상은 실제 전환으로 기록하고, 한 세션에서 1분 이상 사용하면 회고에서 작업의 일부였는지 확인합니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SettingsTheme.accent.opacity(0.04))
    }

    private func appRuleGroupHeader(category: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(category == Self.excludedRuleGroup ? "🚫" : Constants.categoryEmoji(for: category))
            Text(appRuleGroupTitle(category))
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

    private func appRuleGroupTitle(_ category: String) -> String {
        if category == Self.excludedRuleGroup {
            return "기록 안 함"
        }
        if Constants.isProductivityManagementCategory(category) {
            return Constants.productivityManagementAppCategory
        }
        return category
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
                get: {
                    if rule.isExcluded {
                        return Self.excludedRuleGroup
                    }
                    return Constants.isProductivityManagementCategory(rule.category)
                        ? Constants.productivityManagementAppCategory
                        : rule.category
                },
                set: {
                    if $0 == Self.excludedRuleGroup {
                        excludeRule(rule)
                    } else {
                        updateRule(rule, category: $0)
                    }
                }
            )) {
                Text(
                    "\(Constants.productivityManagementAppEmoji) "
                        + Constants.productivityManagementAppCategory
                )
                    .tag(Constants.productivityManagementAppCategory)
                Divider()
                ForEach(Constants.allCategories, id: \.self) { cat in
                    Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                }
                Divider()
                Text("🚫 기록 안 함").tag(Self.excludedRuleGroup)
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
            }

            Button(role: .destructive) {
                deleteRule(rule)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(rule.isUserDefined ? "사용자 규칙 삭제" : "기본 규칙 삭제")
        }
    }

    private func unclassifiedAppRow(_ app: UnclassifiedAppUsage) -> some View {
        SettingsRow(
            app.appName,
            subtitle: "\(formattedDuration(app.durationSeconds)) · \(app.bundleIdentifier)"
        ) {
            Menu("분류 선택") {
                Button(
                    "\(Constants.productivityManagementAppEmoji) "
                        + Constants.productivityManagementAppCategory
                ) {
                    classify(app, as: Constants.productivityManagementAppCategory)
                }
                Divider()
                ForEach(Constants.allCategories, id: \.self) { category in
                    Button("\(Constants.categoryEmoji(for: category)) \(category)") {
                        classify(app, as: category)
                    }
                }
                Divider()
                Button("앞으로 기록 안 함", role: .destructive) {
                    exclude(app)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 112)
        }
    }

    private var addRuleForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "app.fill")
                    .foregroundStyle(SettingsTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(newAppName)
                        .font(.caption.weight(.semibold))
                    Text(newBundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("다른 앱 선택…") {
                    chooseApplication()
                }
                .controlSize(.small)
            }
            HStack {
                Picker("카테고리", selection: $newCategory) {
                    Text(
                        "\(Constants.productivityManagementAppEmoji) "
                            + Constants.productivityManagementAppCategory
                    )
                        .tag(Constants.productivityManagementAppCategory)
                    Divider()
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
                    if upsertUserRule() {
                        showAddRule = false
                        resetRuleForm()
                        loadRules()
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveNewRule)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - 웹사이트 규칙

    private var websiteRulesCard: some View {
        SettingsGroupCard("웹사이트 → 카테고리") {
            VStack(spacing: 0) {
                if websiteRules.isEmpty && !showAddWebsiteRule {
                    Text("등록된 웹사이트 규칙이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(websiteRules) { rule in
                        websiteRuleRow(rule)
                    }
                }

                if showAddWebsiteRule {
                    addWebsiteRuleForm
                }

                HStack {
                    Button {
                        showAddWebsiteRule.toggle()
                    } label: {
                        Label("웹사이트 추가", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("한 번 등록하면 지원되는 모든 브라우저와 하위 도메인에 동일하게 적용됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func websiteRuleRow(_ rule: AppCategoryRule) -> some View {
        let domain = WebsiteCategoryRule.domain(from: rule.bundleIdentifier) ?? rule.appName
        let aliases = Constants.websiteAliases(for: domain)
        let subtitle = aliases.isEmpty
            ? "모든 브라우저 · 하위 도메인 포함"
            : "모든 브라우저 · 하위 도메인 및 \(aliases.joined(separator: ", ")) 포함"
        return SettingsRow(
            domain,
            subtitle: subtitle
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
                ForEach(Constants.allCategories, id: \.self) { category in
                    Text("\(Constants.categoryEmoji(for: category)) \(category)").tag(category)
                }
            }
            .labelsHidden()
            .frame(width: 112)

            Button(role: .destructive) {
                deleteRule(rule)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("웹사이트 규칙 삭제")
        }
    }

    private var addWebsiteRuleForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("예: chatgpt.com 또는 https://chatgpt.com", text: $newWebsiteAddress)
                    .textFieldStyle(.roundedBorder)
                Picker("카테고리", selection: $newWebsiteCategory) {
                    ForEach(Constants.allCategories, id: \.self) { category in
                        Text("\(Constants.categoryEmoji(for: category)) \(category)").tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if !newWebsiteAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(websiteRuleInputMessage)
                    .font(.caption2)
                    .foregroundStyle(canSaveNewWebsiteRule ? Color.secondary : Color.orange)
            }

            HStack {
                Spacer()
                Button("취소") {
                    showAddWebsiteRule = false
                    resetWebsiteRuleForm()
                }
                .controlSize(.small)
                Button("추가") {
                    addWebsiteRule()
                    showAddWebsiteRule = false
                    resetWebsiteRuleForm()
                    loadRules()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveNewWebsiteRule)
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
                Text("같이 쓰는 카테고리 쌍을 등록하면 그 사이 전환은 주의 신호에서 제외합니다.")
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

    private var selectableColorOptions: [CategoryColorOption] {
        let generatedKeys = Set(
            categoryStore.categories
                .compactMap(\.colorKey)
                .filter(CategoryColorPalette.isGenerated)
        )
        return CategoryColorPalette.options
            + generatedKeys.sorted().compactMap(CategoryColorPalette.option)
    }

    private var groupedCategoryRules: [(category: String, rules: [AppCategoryRule])] {
        let grouped = Dictionary(grouping: categoryRules) {
            if $0.isExcluded {
                return Self.excludedRuleGroup
            }
            return Constants.isProductivityManagementCategory($0.category)
                ? Constants.productivityManagementAppCategory
                : $0.category
        }
        return (
            [Constants.productivityManagementAppCategory]
                + Constants.allCategories
                + [Self.excludedRuleGroup]
        )
            .compactMap { category in
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
        return !name.isEmpty
            && !Constants.allCategories.contains(name)
            && !Constants.reservedCategoryNames.contains(name)
    }

    private var newCategoryInputMessage: String? {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if Constants.allCategories.contains(name) {
            return "이미 사용 중인 카테고리 이름입니다."
        }
        if Constants.reservedCategoryNames.contains(name) {
            return "시스템에서 사용하는 카테고리 이름입니다."
        }
        return nil
    }

    private var canSaveNewRule: Bool {
        !trimmedNewBundleId.isEmpty && !trimmedNewAppName.isEmpty
    }

    private var normalizedNewWebsiteDomain: String? {
        WebsiteCategoryRule.normalizedDomain(from: newWebsiteAddress).map(
            Constants.canonicalWebsiteRuleDomain(for:)
        )
    }

    private var canSaveNewWebsiteRule: Bool {
        guard let domain = normalizedNewWebsiteDomain else { return false }
        return !websiteRules.contains {
            WebsiteCategoryRule.domain(from: $0.bundleIdentifier) == domain
        }
    }

    private var websiteRuleInputMessage: String {
        guard let domain = normalizedNewWebsiteDomain else {
            return "올바른 도메인 주소를 입력해 주세요."
        }
        if websiteRules.contains(where: {
            WebsiteCategoryRule.domain(from: $0.bundleIdentifier) == domain
        }) {
            return "\(domain)은 이미 등록되어 있습니다."
        }
        return "\(domain) 및 하위 도메인에 적용됩니다."
    }

    private var trimmedNewBundleId: String {
        newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewAppName: String {
        newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Mutations

    private func setCategoryColor(_ colorKey: String, for category: String) {
        guard categoryStore.setColorKey(colorKey, for: category) else { return }
        NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
    }

    private func resetSessionMarkerColors(for category: String) {
        do {
            let resetCount = try FocusSession.resetMarkerColors(
                for: category,
                in: modelContext
            )
            if resetCount > 0 {
                NotificationCenter.default.post(name: .pomodoroSessionDidChange, object: nil)
            }
        } catch {
            categoryMutationError = error.localizedDescription
        }
    }

    private func updateCategory(oldName: String, newName: String, emoji: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard trimmedName == oldName || !Constants.allCategories.contains(trimmedName) else { return }
        guard trimmedName == oldName
                || !Constants.reservedCategoryNames.contains(trimmedName) else {
            return
        }

        let defaultName = Constants.defaultName(forCategory: oldName)
        if defaultName == "기타", trimmedName != oldName {
            return
        }

        if trimmedName != oldName {
            do {
                try migrateCategory(from: oldName, to: trimmedName)
            } catch {
                categoryMutationError = error.localizedDescription
                return
            }
        }
        guard categoryStore.update(oldName: oldName, newName: trimmedName, emoji: emoji) else { return }
        if trimmedName != oldName {
            applyCategoryMigrationSideEffects(from: oldName, to: trimmedName)
        }
        resetCategorySelections()
        loadRules()
    }

    private func deleteCategory(_ category: String) {
        guard categoryStore.canDelete(category) else { return }
        let fallback = Constants.categoryName("기타")
        do {
            try migrateCategory(
                from: category,
                to: fallback,
                movesBehaviorConditions: false
            )
        } catch {
            categoryMutationError = error.localizedDescription
            return
        }
        categoryStore.delete(name: category)
        applyCategoryMigrationSideEffects(from: category, to: fallback)
        pairStore.removeCategory(category)
        resetCategorySelections()
        loadRules()
    }

    private func migrateCategory(
        from oldName: String,
        to newName: String,
        movesBehaviorConditions: Bool = true
    ) throws {
        guard oldName != newName else { return }
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }

        let oldCategory = oldName
        let newCategory = newName

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.category == oldCategory }
        )
        do {
            for segment in try modelContext.fetch(segmentDescriptor) {
                segment.category = newCategory
            }

            let recordDescriptor = FetchDescriptor<AppUsageRecord>(
                predicate: #Predicate { $0.category == oldCategory }
            )
            for record in try modelContext.fetch(recordDescriptor) {
                record.category = newCategory
            }

            let focusDescriptor = FetchDescriptor<FocusSession>()
            for session in try modelContext.fetch(focusDescriptor)
                where session.category == oldCategory {
                session.category = newCategory
            }

            let ruleDescriptor = FetchDescriptor<AppCategoryRule>(
                predicate: #Predicate { $0.category == oldCategory }
            )
            for rule in try modelContext.fetch(ruleDescriptor) {
                rule.category = newCategory
                if let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier),
                   defaultRule.category == newCategory {
                    rule.isUserDefined = false
                } else {
                    rule.isUserDefined = true
                }
            }

            if movesBehaviorConditions {
                try CategoryBehaviorConditionSetStore.prepareCategoryRename(
                    from: oldCategory,
                    to: newCategory,
                    modelContext: modelContext
                )
            } else {
                try CategoryBehaviorConditionSetStore.prepareCategoryDeletion(
                    category: oldCategory,
                    modelContext: modelContext
                )
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func applyCategoryMigrationSideEffects(
        from oldCategory: String,
        to newCategory: String
    ) {
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
        CategoryManager.shared.loadUserRules(from: modelContext)
    }

    private func resetCategorySelections() {
        let categories = Constants.allCategories
        if newCategory != Constants.productivityManagementAppCategory
            && !categories.contains(newCategory) {
            newCategory = categories.first ?? Constants.categoryName("기타")
        }
        if !categories.contains(newWebsiteCategory) {
            newWebsiteCategory = categories.first ?? Constants.categoryName("기타")
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

    private func resetWebsiteRuleForm() {
        newWebsiteAddress = ""
        newWebsiteCategory = Constants.categoryName("기타")
    }

    private func loadRules() {
        insertMissingDefaultRules()
        CategoryManager.shared.loadUserRules(from: modelContext)
        var descriptor = FetchDescriptor<AppCategoryRule>()
        descriptor.sortBy = [
            SortDescriptor(\AppCategoryRule.category),
            SortDescriptor(\AppCategoryRule.appName),
        ]
        let allRules = (try? modelContext.fetch(descriptor)) ?? []
        categoryRules = allRules.filter {
            WebsiteCategoryRule.domain(from: $0.bundleIdentifier) == nil
        }
        websiteRules = allRules.filter {
            WebsiteCategoryRule.domain(from: $0.bundleIdentifier) != nil
        }
        .sorted {
            $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
        unclassifiedApps = AppClassificationService.allUnclassifiedApps(
            modelContext: modelContext
        )
    }

    private func insertMissingDefaultRules() {
        try? DefaultAppCategoryRuleStore.reconcile(in: modelContext)
    }

    @discardableResult
    private func upsertUserRule() -> Bool {
        let bundleId = trimmedNewBundleId
        let appName = trimmedNewAppName
        guard !bundleId.isEmpty, !appName.isEmpty else { return false }

        if let existing = categoryRules.first(where: { $0.bundleIdentifier == bundleId }) {
            requestRuleCategoryChange(
                existing,
                category: newCategory,
                replacementAppName: appName,
                closesAddRuleForm: true
            )
            return false
        }

        Constants.restoreDefaultCategoryRule(bundleId)
        let rule = AppCategoryRule(
            bundleIdentifier: bundleId,
            appName: appName,
            category: newCategory,
            isUserDefined: true
        )
        modelContext.insert(rule)
        do {
            try AppClassificationService.reclassifyUnclassifiedUsage(
                bundleIdentifier: bundleId,
                category: newCategory,
                modelContext: modelContext
            )
            CategoryManager.shared.setUserRule(
                bundleIdentifier: bundleId,
                category: newCategory
            )
            return true
        } catch {
            modelContext.rollback()
            categoryMutationError = error.localizedDescription
            return false
        }
    }

    private func addWebsiteRule() {
        guard let domain = normalizedNewWebsiteDomain else { return }
        let bundleIdentifier = WebsiteCategoryRule.bundleIdentifier(for: domain)
        let rule = AppCategoryRule(
            bundleIdentifier: bundleIdentifier,
            appName: domain,
            category: newWebsiteCategory,
            isUserDefined: true
        )
        modelContext.insert(rule)
        try? modelContext.save()
        CategoryManager.shared.setUserRule(
            bundleIdentifier: bundleIdentifier,
            category: newWebsiteCategory
        )
    }

    private func updateRule(_ rule: AppCategoryRule, category: String) {
        requestRuleCategoryChange(rule, category: category)
    }

    private func excludeRule(_ rule: AppCategoryRule) {
        try? AppClassificationService.exclude(
            bundleIdentifier: rule.bundleIdentifier,
            appName: rule.appName,
            modelContext: modelContext
        )
        loadRules()
    }

    private func canResetRule(_ rule: AppCategoryRule) -> Bool {
        guard let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier, includingHidden: true) else { return false }
        return rule.isUserDefined || rule.category != defaultRule.category
    }

    private func resetRuleToDefault(_ rule: AppCategoryRule) {
        guard let defaultRule = Constants.defaultCategoryRule(for: rule.bundleIdentifier, includingHidden: true) else { return }
        requestRuleCategoryChange(
            rule,
            category: defaultRule.category,
            replacementAppName: defaultRule.appName
        )
    }

    private var ruleCategoryChangeMessage: String {
        guard let change = pendingRuleCategoryChange else {
            return "앞으로 기록되는 데이터에만 적용할지 선택해 주세요."
        }
        return "\(change.displayName)의 카테고리를 '\(change.oldCategory)'에서 '\(change.newCategory)'로 변경합니다. 사용자가 직접 수정한 세션 기록은 그대로 유지됩니다."
    }

    private func requestRuleCategoryChange(
        _ rule: AppCategoryRule,
        category: String,
        replacementAppName: String? = nil,
        closesAddRuleForm: Bool = false
    ) {
        let change = PendingRuleCategoryChange(
            rule: rule,
            displayName: replacementAppName ?? rule.appName,
            oldCategory: rule.category,
            newCategory: category,
            replacementAppName: replacementAppName,
            closesAddRuleForm: closesAddRuleForm
        )

        guard rule.category != category else {
            pendingRuleCategoryChange = change
            applyPendingRuleCategoryChange(includeExistingUsage: false)
            return
        }
        pendingRuleCategoryChange = change
    }

    private func applyPendingRuleCategoryChange(includeExistingUsage: Bool) {
        guard let change = pendingRuleCategoryChange else { return }
        let rule = change.rule
        let bundleIdentifier = rule.bundleIdentifier

        if let replacementAppName = change.replacementAppName {
            rule.appName = replacementAppName
        }
        rule.category = change.newCategory
        rule.isExcluded = false
        Constants.restoreDefaultCategoryRule(bundleIdentifier)
        if let defaultRule = Constants.defaultCategoryRule(for: bundleIdentifier),
           defaultRule.category == change.newCategory {
            rule.isUserDefined = false
        } else {
            rule.isUserDefined = true
        }

        do {
            if includeExistingUsage {
                try AppClassificationService.reclassifyExistingUsage(
                    ruleBundleIdentifier: bundleIdentifier,
                    category: change.newCategory,
                    modelContext: modelContext
                )
            } else {
                try modelContext.save()
            }

            if rule.isUserDefined {
                CategoryManager.shared.setUserRule(
                    bundleIdentifier: bundleIdentifier,
                    category: change.newCategory
                )
            } else {
                CategoryManager.shared.removeUserRule(
                    bundleIdentifier: bundleIdentifier
                )
            }
            if change.closesAddRuleForm {
                showAddRule = false
                resetRuleForm()
            }
            pendingRuleCategoryChange = nil
            loadRules()
        } catch {
            modelContext.rollback()
            pendingRuleCategoryChange = nil
            categoryMutationError = error.localizedDescription
            loadRules()
        }
    }

    private func deleteRule(_ rule: AppCategoryRule) {
        if Constants.defaultCategoryRule(for: rule.bundleIdentifier, includingHidden: true) != nil {
            Constants.hideDefaultCategoryRule(rule.bundleIdentifier)
        }
        modelContext.delete(rule)
        try? modelContext.save()
        CategoryManager.shared.removeUserRule(bundleIdentifier: rule.bundleIdentifier)
        loadRules()
    }

    private func classify(_ app: UnclassifiedAppUsage, as category: String) {
        do {
            try AppClassificationService.classify(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.appName,
                category: category,
                modelContext: modelContext
            )
            loadRules()
        } catch {
            categoryMutationError = error.localizedDescription
        }
    }

    private func exclude(_ app: UnclassifiedAppUsage) {
        do {
            try AppClassificationService.exclude(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.appName,
                modelContext: modelContext
            )
            loadRules()
        } catch {
            categoryMutationError = error.localizedDescription
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "카테고리에 등록할 앱 선택"
        panel.prompt = "선택"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return
        }

        let displayName = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
        let bundleName = bundle.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String
        newBundleId = bundleIdentifier
        newAppName = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
        showAddRule = true
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = max(0, seconds) / 3_600
        let minutes = (max(0, seconds) % 3_600) / 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        if minutes > 0 { return "\(minutes)분" }
        return "\(max(0, seconds))초"
    }
}
