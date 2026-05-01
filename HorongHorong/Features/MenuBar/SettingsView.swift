import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var launchAtLogin: Bool = false
    @State private var categoryRules: [AppCategoryRule] = []
    @State private var categoryStore = CategoryStore.shared
    @State private var showAddRule: Bool = false
    @State private var newBundleId: String = ""
    @State private var newAppName: String = ""
    @State private var newCategory: String = Constants.categoryName("기타")
    @State private var showAddCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryEmoji: String = "📦"
    @AppStorage(Constants.AppStorageKey.interestKeywords) private var interestKeywords = Constants.defaultInterestKeywords
    @AppStorage(Constants.AppStorageKey.pomodoroFocusMinutes)
    private var pomodoroFocusMinutes: Int = Constants.defaultPomodoroFocusMinutes
    @AppStorage(Constants.AppStorageKey.pomodoroBreakMinutes)
    private var pomodoroBreakMinutes: Int = Constants.defaultPomodoroBreakMinutes
    @AppStorage(Constants.AppStorageKey.longFocusFocusMinutes)
    private var longFocusFocusMinutes: Int = Constants.defaultLongFocusFocusMinutes
    @AppStorage(Constants.AppStorageKey.longFocusBreakMinutes)
    private var longFocusBreakMinutes: Int = Constants.defaultLongFocusBreakMinutes
    @AppStorage(Constants.AppStorageKey.timelineStartHour)
    private var timelineStartHour: Int = Constants.defaultTimelineStartHour
    @AppStorage(Constants.AppStorageKey.timelineEndHour)
    private var timelineEndHour: Int = Constants.defaultTimelineEndHour
    @AppStorage(Constants.AppStorageKey.timelineBucketMinutes)
    private var timelineBucketMinutes: Int = Constants.defaultTimelineBucketMinutes
    @State private var idleThresholdStore = IdleThresholdStore.shared
    @State private var pairStore = CategoryPairStore.shared
    @State private var showAddPair: Bool = false
    @State private var newPairA: String = Constants.allCategories.first ?? Constants.categoryName("기타")
    @State private var newPairB: String = Constants.allCategories.dropFirst().first ?? Constants.allCategories.first ?? Constants.categoryName("기타")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timerSettings
                Divider()
                shortcutSettings
                Divider()
                launchSettings
                Divider()
                interestSettings
                Divider()
                categoryDefinitionSettings
                Divider()
                idleThresholdSettings
                Divider()
                timelineDisplaySettings
                Divider()
                categoryPairSettings
                Divider()
                categorySettings
                Divider()
                versionFooter
            }
        }
    }

    private var versionFooter: some View {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return HStack {
            Spacer()
            Text("호롱호롱 v\(marketing) (build \(build))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var timerSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("타이머 설정", systemImage: "timer")
                .font(.headline)

            @Bindable var state = appState

            Text("타이머에서 프리셋 선택 시 아래 값이 적용됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                presetRow(
                    title: "🍅 포모도로",
                    focusBinding: $pomodoroFocusMinutes,
                    breakBinding: $pomodoroBreakMinutes,
                    focusRange: 1...120,
                    breakRange: 1...30
                )
                Divider()
                presetRow(
                    title: "🔥 긴 집중",
                    focusBinding: $longFocusFocusMinutes,
                    breakBinding: $longFocusBreakMinutes,
                    focusRange: 1...240,
                    breakRange: 1...60
                )
                Divider()
                presetRow(
                    title: "⚙️ 커스텀",
                    focusBinding: $state.focusMinutes,
                    breakBinding: $state.breakMinutes,
                    focusRange: 1...240,
                    breakRange: 1...60
                )
            }

            Button("프리셋 기본값으로 되돌리기") {
                pomodoroFocusMinutes = Constants.defaultPomodoroFocusMinutes
                pomodoroBreakMinutes = Constants.defaultPomodoroBreakMinutes
                longFocusFocusMinutes = Constants.defaultLongFocusFocusMinutes
                longFocusBreakMinutes = Constants.defaultLongFocusBreakMinutes
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    private func presetRow(
        title: String,
        focusBinding: Binding<Int>,
        breakBinding: Binding<Int>,
        focusRange: ClosedRange<Int>,
        breakRange: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
                .frame(width: 88, alignment: .leading)

            HStack(spacing: 4) {
                Text("집중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NumberField(value: focusBinding, range: focusRange, suffix: "분", width: 44)
            }

            HStack(spacing: 4) {
                Text("휴식")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NumberField(value: breakBinding, range: breakRange, suffix: "분", width: 40)
            }

            Spacer(minLength: 0)
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("글로벌 단축키", systemImage: "keyboard")
                .font(.headline)

            HStack {
                Text("퀵 메모")
                    .font(.callout)
                Spacer()
                Text("⌘ + Shift + N")
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var launchSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("일반", systemImage: "gearshape")
                .font(.headline)

            Toggle("로그인 시 자동 시작", isOn: $launchAtLogin)
                .font(.callout)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("자동 시작 설정 실패: \(error)")
                        launchAtLogin = !newValue
                    }
                }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var categorySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("앱 카테고리 관리", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Button {
                    showAddRule.toggle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            if showAddRule {
                addRuleForm
            }

            if categoryRules.isEmpty {
                Text("등록된 앱 규칙이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(groupedCategoryRules, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(Constants.categoryEmoji(for: group.category))
                            Text(group.category)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(group.rules.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.rules) { rule in
                            appRuleRow(rule)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { loadRules() }
    }

    private var categoryDefinitionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("카테고리 관리", systemImage: "tag")
                    .font(.headline)
                Spacer()
                Button {
                    showAddCategory.toggle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            Text("이름 변경은 기존 통계 기록과 앱 규칙까지 함께 바꿉니다. 삭제하면 해당 기록은 기타로 이동합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showAddCategory {
                addCategoryForm
            }

            ForEach(categoryStore.categories) { category in
                categoryDefinitionRow(category)
            }
        }
    }

    private var addCategoryForm: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("이모지", text: $newCategoryEmoji)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 56)
                TextField("카테고리 이름", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
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
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func categoryDefinitionRow(_ category: CategoryDefinition) -> some View {
        HStack(spacing: 8) {
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
            .disabled(category.defaultName == "기타")

            if category.defaultName != category.name {
                Text("변경됨")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if category.defaultName != category.name || category.emoji != (Constants.categoryEmoji[category.defaultName] ?? category.emoji) {
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
        CategoryPairStore.shared.removeCategory(category)
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

    private func appRuleRow(_ rule: AppCategoryRule) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(rule.appName)
                        .font(.callout)
                    Text(rule.isUserDefined ? "사용자" : "기본")
                        .font(.caption2)
                        .foregroundStyle(rule.isUserDefined ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(rule.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Picker("", selection: Binding(
                get: { rule.category },
                set: { updateRule(rule, category: $0) }
            )) {
                ForEach(Constants.allCategories, id: \.self) { cat in
                    Text("\(Constants.categoryEmoji(for: cat)) \(cat)").tag(cat)
                }
            }
            .labelsHidden()
            .frame(width: 92)

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
                    .help("기본 규칙은 삭제하지 않고 카테고리 수정 또는 기본값 복원만 지원합니다")
            }
        }
        .padding(.vertical, 3)
    }

    private var idleThresholdSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("자리 비움 감지 임계값", systemImage: "moon.zzz")
                .font(.headline)

            Text("입력이 N분 이상 없으면 복귀 시 \"작업 시간으로 인정할까요?\" 를 물어봅니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Constants.allCategories, id: \.self) { category in
                idleThresholdRow(for: category)
            }
        }
    }

    private func idleThresholdRow(for category: String) -> some View {
        HStack(spacing: 8) {
            Text(Constants.categoryEmoji(for: category))
            Text(category)
                .font(.callout)
                .frame(width: 40, alignment: .leading)
            Spacer()
            NumberField(
                value: Binding(
                    get: { idleThresholdStore.minutes(for: category) },
                    set: { idleThresholdStore.setMinutes($0, for: category) }
                ),
                range: 1...180,
                suffix: "분",
                width: 52
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

    private var timelineDisplaySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("타임라인 표시", systemImage: "rectangle.split.3x1")
                .font(.headline)

            Text("일간 \"시간대별 작업\" 차트에 보여줄 시간 범위와 간격")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("시작 시간")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $timelineStartHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text("\(h)시").tag(h)
                    }
                }
                .labelsHidden()
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("종료 시간")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $timelineEndHour) {
                    ForEach(1...24, id: \.self) { h in
                        Text(h == 24 ? "24시" : "\(h)시").tag(h)
                    }
                }
                .labelsHidden()
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("시간 간격")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $timelineBucketMinutes) {
                    ForEach(Constants.timelineBucketMinuteOptions, id: \.self) { m in
                        Text("\(m)분").tag(m)
                    }
                }
                .labelsHidden()
                Spacer(minLength: 0)
            }

            if timelineStartHour >= timelineEndHour {
                Text("⚠️ 시작 시간이 종료 시간보다 늦거나 같습니다")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var categoryPairSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("짝 카테고리 (전환 무시)", systemImage: "arrow.triangle.swap")
                    .font(.headline)
                Spacer()
                Button {
                    showAddPair.toggle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            Text("같이 쓰는 카테고리 쌍을 등록하면 그 둘 사이 전환은 산만 카운트에서 제외합니다. 예: 개발 ↔ 소통. 타이머를 사용하는 동안의 전환도 자동으로 제외됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showAddPair {
                addPairForm
            }

            if pairStore.pairs.isEmpty {
                Text("등록된 짝이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(pairStore.pairs, id: \.self) { pair in
                    HStack(spacing: 8) {
                        Text("\(Constants.categoryEmoji(for: pair.first)) \(pair.first)")
                            .font(.callout)
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Constants.categoryEmoji(for: pair.second)) \(pair.second)")
                            .font(.callout)
                        Spacer()
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
        }
    }

    private var addPairForm: some View {
        VStack(spacing: 6) {
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
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var interestSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("사용자 관심사 키워드", systemImage: "sparkles")
                .font(.headline)

            Text("쉼표(,)로 구분해 입력하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("예: 생산성, 자동화, 데이터 시각화", text: $interestKeywords)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            if interestKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("비어 있으면 Agent 실험 탭에서 기본값이 사용됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var addRuleForm: some View {
        VStack(spacing: 6) {
            TextField("번들 ID (예: com.example.app)", text: $newBundleId)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            TextField("앱 이름", text: $newAppName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            Picker("카테고리", selection: $newCategory) {
                ForEach(Constants.allCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .font(.caption)

            HStack {
                Spacer()
                Button("취소") {
                    showAddRule = false
                    resetForm()
                }
                .controlSize(.small)
                Button("추가") {
                    upsertUserRule()
                    try? modelContext.save()
                    showAddRule = false
                    resetForm()
                    loadRules()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveNewRule)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private var canSaveNewRule: Bool {
        !trimmedNewBundleId.isEmpty && !trimmedNewAppName.isEmpty
    }

    private var trimmedNewBundleId: String {
        newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewAppName: String {
        newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func resetForm() {
        newBundleId = ""
        newAppName = ""
        newCategory = Constants.categoryName("기타")
    }
}
