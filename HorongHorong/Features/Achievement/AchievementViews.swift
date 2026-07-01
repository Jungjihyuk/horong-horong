import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

private enum AchievementRewardStatus {
    case pending
    case earned

    var label: String {
        switch self {
        case .pending: return "대기"
        case .earned: return "완료"
        }
    }
}

private enum AchievementTodoStatus {
    case done
    case pending
    case future
}

private struct AchievementReward {
    let amount: String
    let status: AchievementRewardStatus
}

private struct AchievementTodo: Identifiable {
    let id: UUID
    let text: String
    let when: String
    let detail: String
    let status: AchievementTodoStatus

    var metaText: String {
        when.isEmpty ? detail : "\(when) · \(detail)"
    }
}

private struct AchievementGoal: Identifiable {
    let id: UUID
    let emoji: String
    let title: String
    let cadence: String
    let rule: String
    let done: Int
    let total: Int
    let reward: AchievementReward
    let color: Color
    let todos: [AchievementTodo]
    let roleName: String
    let vision: String
    let yearGoal: String?
    let quarterGoal: String?
    let monthGoal: String?
    let recordDate: Date
    let sourceMemoIDs: [UUID]

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var isComplete: Bool {
        done >= total
    }

    var nextTodo: AchievementTodo? {
        todos.first { $0.status == .pending } ?? todos.first
    }
}

private struct AchievementRole: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let vision: String
}

private enum AchievementJourneyImageStore {
    private static let defaultsKey = "achievementJourneyImagePaths"

    static func imageURL(for roleID: String) -> URL? {
        guard let path = imagePaths()[roleID] else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func saveImage(from sourceURL: URL, for roleID: String) throws -> URL {
        let directory = try imageDirectory()
        var paths = imagePaths()
        if let previousPath = paths[roleID] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: previousPath))
        }

        let destination = directory
            .appendingPathComponent(sanitized(roleID), isDirectory: false)
            .appendingPathExtension("jpg")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if let image = NSImage(contentsOf: sourceURL),
           let data = jpegData(for: image, maxPixelLength: 1200) {
            try data.write(to: destination, options: .atomic)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }

        paths[roleID] = destination.path
        UserDefaults.standard.set(paths, forKey: defaultsKey)
        return destination
    }

    static func removeImage(for roleID: String) {
        var paths = imagePaths()
        if let path = paths[roleID] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        paths.removeValue(forKey: roleID)
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private static func imagePaths() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func imageDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("HorongHorong/JourneyImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? UUID().uuidString : result
    }

    private static func jpegData(for image: NSImage, maxPixelLength: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixelLength / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else { return nil }
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }
}

private struct AchievementTimelineItem: Identifiable {
    let id = UUID()
    let date: Date
    let weekday: String
    let topLabel: String?
    let todos: [AchievementTimelineTodo]
    let isCompleted: Bool
    let isFuture: Bool
    let isReward: Bool
}

private struct AchievementTimelineTodo: Identifiable {
    let id: UUID
    let memoID: UUID
    let title: String
    let meta: String
    let isCompleted: Bool
    let isFuture: Bool
}

private enum AchievementTimelineDragPayload {
    static let prefix = "horong-achievement-memo:"

    static func string(for memoID: UUID) -> String {
        "\(prefix)\(memoID.uuidString)"
    }

    static func memoID(from text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }
}

private struct AchievementMonthlyWeekProgress: Identifiable {
    let id = UUID()
    let week: Int
    let completed: Int
    let total: Int
    let isCurrent: Bool

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var percentText: String {
        "\(Int(round(progress * 100)))%"
    }
}

private struct AchievementGoalEditDraft {
    let title: String
    let emoji: String
    let rule: String
    let targetCount: Int
    let rewardText: String
    let linkedMemoIDs: [UUID]?
}

private struct AchievementPersonaVisionDraft {
    let personaName: String
    let personaEmoji: String
    let visionTitle: String
    let visionText: String
    let visionEmoji: String
}

private enum AchievementJourneyFlagStore {
    private static var defaultsKey: String { Constants.AppStorageKey.achievementJourneyFlagSelections }
    private static let emptySlot = "-"

    static func goalIDs(for key: String, maxCount: Int) -> [UUID?] {
        guard let value = flagSelections()[key] else { return [] }
        return Array(value
            .split(separator: ",", omittingEmptySubsequences: false)
            .prefix(maxCount)
            .map { item -> UUID? in
                let text = String(item)
                return text == emptySlot ? nil : UUID(uuidString: text)
            })
    }

    static func setGoalID(_ goalID: UUID?, at index: Int, for key: String, maxCount: Int) {
        guard index >= 0, index < maxCount else { return }
        var ids = goalIDs(for: key, maxCount: maxCount)
        while ids.count < maxCount {
            ids.append(nil)
        }

        ids[index] = goalID

        let encoded = ids
            .prefix(maxCount)
            .map { $0?.uuidString ?? emptySlot }
            .joined(separator: ",")
        var selections = flagSelections()
        selections[key] = encoded
        UserDefaults.standard.set(selections, forKey: defaultsKey)
    }

    private static func flagSelections() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

private enum AchievementGoalSuggestionSource: String, Sendable {
    case rule = "룰 기반"
    case foundationModel = "Apple 모델"
}

private enum AchievementGoalSuggestionTarget: String, Sendable {
    case weekly = "주간목표"
    case monthly = "월간목표"

    var cadence: String {
        switch self {
        case .weekly: return "주간"
        case .monthly: return "월간"
        }
    }

    var periodText: String {
        switch self {
        case .weekly: return "이번 주"
        case .monthly: return "이번 달"
        }
    }
}

private struct AchievementMemoSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let content: String
    let icon: String?
    let date: Date
    let startDate: Date?
    let deadline: Date?
    let isCompleted: Bool
}

private struct AchievementGoalSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let emoji: String
    let rule: String
    let done: Int
    let total: Int
    let sourceMemoIDs: [UUID]
    let roleName: String
    let vision: String
    let monthGoal: String?
}

private struct AchievementGoalSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let reason: String
    let memoIDs: [UUID]
    let childGoalIDs: [UUID]
    let scheduleText: String
    let criterion: String
    let targetValueText: String
    let emoji: String
    let target: AchievementGoalSuggestionTarget
    let source: AchievementGoalSuggestionSource

    init(
        id: UUID = UUID(),
        title: String,
        reason: String,
        memoIDs: [UUID],
        childGoalIDs: [UUID] = [],
        scheduleText: String,
        criterion: String,
        targetValueText: String,
        emoji: String,
        target: AchievementGoalSuggestionTarget = .weekly,
        source: AchievementGoalSuggestionSource
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.memoIDs = Array(Set(memoIDs))
        self.childGoalIDs = Array(Set(childGoalIDs))
        self.scheduleText = scheduleText
        self.criterion = criterion
        self.targetValueText = targetValueText
        self.emoji = emoji
        self.target = target
        self.source = source
    }
}

private enum AchievementGoalSuggestionBuilder {
    static func ruleBasedSuggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> [AchievementGoalSuggestion] {
        let pending = memos.filter { !$0.isCompleted }
        let source = pending.isEmpty ? memos : pending
        var suggestions: [AchievementGoalSuggestion] = []

        suggestions.append(contentsOf: groupedByKeyword(from: source, maxMemoCount: maxMemoCount))

        return deduplicated(suggestions)
            .sorted { lhs, rhs in
                if lhs.memoIDs.count == rhs.memoIDs.count {
                    return lhs.title < rhs.title
                }
                return lhs.memoIDs.count > rhs.memoIDs.count
            }
            .prefix(suggestionCount)
            .map { $0 }
    }

    static func snapshots(from memos: [Memo]) -> [AchievementMemoSnapshot] {
        memos.map { memo in
            AchievementMemoSnapshot(
                id: memo.id,
                content: memo.content,
                icon: memo.icon,
                date: AchievementDataBuilder.memoDate(memo),
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompletedValue
            )
        }
    }

    static func snapshots(from goals: [AchievementGoal]) -> [AchievementGoalSnapshot] {
        goals.map { goal in
            AchievementGoalSnapshot(
                id: goal.id,
                title: goal.title,
                emoji: goal.emoji,
                rule: goal.rule,
                done: goal.done,
                total: goal.total,
                sourceMemoIDs: goal.sourceMemoIDs,
                roleName: goal.roleName,
                vision: goal.vision,
                monthGoal: goal.monthGoal
            )
        }
    }

    static func monthlyRuleBasedSuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int
    ) -> [AchievementGoalSuggestion] {
        let candidates = goals.filter { goal in
            goal.monthGoal?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        let source = candidates.count >= 2 ? candidates : goals
        var suggestions: [AchievementGoalSuggestion] = []

        suggestions.append(contentsOf: groupedMonthlyByContext(from: source))
        suggestions.append(contentsOf: groupedMonthlyByKeyword(from: source))
        suggestions.append(contentsOf: groupedMonthlyFallback(from: source))

        return deduplicatedMonthly(suggestions)
            .sorted { lhs, rhs in
                if lhs.childGoalIDs.count == rhs.childGoalIDs.count {
                    return lhs.title < rhs.title
                }
                return lhs.childGoalIDs.count > rhs.childGoalIDs.count
            }
            .prefix(suggestionCount)
            .map { $0 }
    }

    private static func groupedByIcon(from memos: [AchievementMemoSnapshot], maxMemoCount: Int) -> [AchievementGoalSuggestion] {
        Dictionary(grouping: memos, by: { $0.icon ?? MemoIcon.defaultIcon })
            .compactMap { icon, items in
                guard items.count >= 2 else { return nil }
                let limited = limitedMemos(items, maxMemoCount: maxMemoCount)
                return suggestion(
                    title: weeklyTitle(for: limited),
                    reason: "같은 아이콘의 할일 \(limited.count)개가 모여 있습니다.",
                    memos: limited,
                    emoji: icon,
                    source: .rule
                )
            }
    }

    private static func groupedByKeyword(from memos: [AchievementMemoSnapshot], maxMemoCount: Int) -> [AchievementGoalSuggestion] {
        let keywordGroups: [(keywords: [String], emoji: String, title: String)] = [
            (["이력서", "포트폴리오", "채용", "지원", "공고"], "💼", "지원 준비"),
            (["버그", "오류", "크래시", "수정"], "🛠", "오류 수정"),
            (["리팩터", "구조 개선", "고도화"], "💻", "구조 개선"),
            (["문서화", "README", "명세서", "정의서"], "📝", "문서화"),
            (["논문", "요약", "리서치"], "📚", "리서치 정리"),
            (["운동", "헬스", "러닝", "사이클"], "🏃", "운동 루틴"),
        ]

        return keywordGroups.compactMap { group in
            let items = memos.filter { memo in
                group.keywords.contains { memo.content.localizedCaseInsensitiveContains($0) }
            }
            guard items.count >= 2 else { return nil }
            let limited = limitedMemos(items, maxMemoCount: maxMemoCount)
            return suggestion(
                title: "\(group.title) 목표",
                reason: "\(group.title)에 직접 연결된 할일 \(limited.count)개를 묶었습니다.",
                memos: limited,
                emoji: group.emoji,
                source: .rule
            )
        }
    }

    private static func groupedByWeek(from memos: [AchievementMemoSnapshot], maxMemoCount: Int) -> [AchievementGoalSuggestion] {
        let calendar = Calendar.current
        let today = Date()
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let items = memos.filter { week.contains($0.date) }
        guard items.count >= 2 else { return [] }
        let limited = limitedMemos(items, maxMemoCount: maxMemoCount)
        return [
            suggestion(
                title: weeklyTitle(for: limited),
                reason: "이번 주 일정에 들어온 할일을 한 목표로 묶었습니다.",
                memos: limited,
                emoji: "🎯",
                source: .rule
            ),
        ]
    }

    private static func suggestion(
        title: String,
        reason: String,
        memos: [AchievementMemoSnapshot],
        emoji: String,
        source: AchievementGoalSuggestionSource
    ) -> AchievementGoalSuggestion {
        let count = memos.count
        return AchievementGoalSuggestion(
            title: title,
            reason: reason,
            memoIDs: memos.map(\.id),
            scheduleText: scheduleText(for: memos),
            criterion: "연결한 할일 \(count)개 완료",
            targetValueText: "\(count)개",
            emoji: emoji,
            source: source
        )
    }

    private static func scheduleText(for memos: [AchievementMemoSnapshot]) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"

        let weekdays = Array(Set(memos.map { formatter.string(from: $0.date) })).sorted()
        if weekdays.isEmpty {
            return "이번 주에 나눠 진행"
        }
        if weekdays.count <= 3 {
            return "\(weekdays.joined(separator: "/"))에 나눠 진행"
        }
        let todayCount = memos.filter { calendar.isDateInToday($0.date) }.count
        return todayCount > 0 ? "오늘 \(todayCount)개부터 진행" : "이번 주에 나눠 진행"
    }

    private static func limitedMemos(_ memos: [AchievementMemoSnapshot], maxMemoCount: Int) -> [AchievementMemoSnapshot] {
        Array(memos.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.content < rhs.content
            }
            return lhs.date < rhs.date
        }.prefix(max(2, maxMemoCount)))
    }

    private static func weeklyTitle(for memos: [AchievementMemoSnapshot]) -> String {
        if let phrase = representativePhrase(from: memos.map(\.content)) {
            return "\(phrase) 목표"
        }
        return "할일 \(memos.count)개 묶음"
    }

    private static func monthlyTitle(for goals: [AchievementGoalSnapshot], context: String? = nil) -> String {
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(AchievementDataBuilder.shortText(context, limit: 18)) 목표"
        }
        let texts = goals.flatMap { [$0.title, $0.rule] }
        if let phrase = representativePhrase(from: texts) {
            return "\(phrase) 월간 목표"
        }
        let titles = goals.prefix(2).map { AchievementDataBuilder.shortText($0.title, limit: 12) }
        if titles.count >= 2 {
            return "\(titles.joined(separator: " · ")) 연결"
        }
        return "주간 목표 \(goals.count)개 묶음"
    }

    private static func representativePhrase(from texts: [String]) -> String? {
        let phrases = texts
            .flatMap(candidatePhrases(from:))
            .filter { !isNoisyTitleToken($0) }
        let phraseCounts = Dictionary(grouping: phrases, by: { $0 }).mapValues(\.count)
        if let phrase = phraseCounts.sorted(by: titleCandidateSort).first?.key {
            return phrase
        }
        return representativeToken(from: texts)
    }

    private static func candidatePhrases(from text: String) -> [String] {
        let cleaned = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("/")
                    && !trimmed.hasPrefix("#")
                    && !trimmed.hasPrefix("@")
                    && !trimmed.localizedCaseInsensitiveContains("://")
            }
            .joined(separator: " ")
        let separators = CharacterSet(charactersIn: ",.?!|·&()[]{}<>")
            .union(.newlines)
        return cleaned
            .components(separatedBy: separators)
            .map { value in
                value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "  ", with: " ")
            }
            .filter { value in
                value.count >= 4
                    && value.count <= 18
                    && value.range(of: #"[가-힣]"#, options: .regularExpression) != nil
                    && !isNoisyTitleToken(value)
            }
            .map { AchievementDataBuilder.shortText($0, limit: 16) }
    }

    private static func representativeToken(from texts: [String]) -> String? {
        let ignored: Set<String> = [
            "하기", "완료", "진행", "목표", "이번", "주간", "월간", "할일", "메모",
            "연결", "정도", "이상", "이하", "오늘", "내일", "일정", "달성",
            "markdown", "kakaotalk", "obsidian", "agent",
        ]
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let tokens = texts
            .flatMap { $0.components(separatedBy: separators) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                token.count >= 2
                    && !ignored.contains(token)
                    && !ignored.contains(token.lowercased())
                    && !isNoisyTitleToken(token)
                    && token.range(of: #"[가-힣]"#, options: .regularExpression) != nil
                    && token.rangeOfCharacter(from: .letters) != nil
            }

        let counts = Dictionary(grouping: tokens, by: { $0 }).mapValues(\.count)
        return counts.sorted(by: titleCandidateSort)
        .first?
        .key
    }

    private static func titleCandidateSort(_ lhs: (key: String, value: Int), _ rhs: (key: String, value: Int)) -> Bool {
        if lhs.value == rhs.value {
            return lhs.key.count > rhs.key.count
        }
        return lhs.value > rhs.value
    }

    private static func isNoisyTitleToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("#") || trimmed.hasPrefix("@") {
            return true
        }
        if lowercased.contains("agent-") || lowercased.contains("kakaotalk") || lowercased.contains("markdown") {
            return true
        }
        if lowercased.contains("http://") || lowercased.contains("https://") {
            return true
        }
        if trimmed.range(of: #"\d{6,}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func groupedMonthlyByContext(from goals: [AchievementGoalSnapshot]) -> [AchievementGoalSuggestion] {
        let groups = Dictionary(grouping: goals) { goal in
            [
                goal.roleName.trimmingCharacters(in: .whitespacesAndNewlines),
                goal.vision.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        }

        return groups.compactMap { key, items in
            guard !key.isEmpty, items.count >= 2 else { return nil }
            let limited = limitedGoals(items)
            return monthlySuggestion(
                title: monthlyTitle(for: limited, context: key),
                reason: "같은 페르소나나 비전으로 이어지는 주간 목표 \(limited.count)개를 묶었습니다.",
                goals: limited,
                emoji: limited.first?.emoji ?? "📅",
                source: .rule
            )
        }
    }

    private static func groupedMonthlyByKeyword(from goals: [AchievementGoalSnapshot]) -> [AchievementGoalSuggestion] {
        let keywordGroups: [(keywords: [String], emoji: String)] = [
            (["이력서", "포트폴리오", "지원", "면접", "채용", "커리어"], "💼"),
            (["개발", "구현", "버그", "릴리즈", "v0", "앱", "호롱"], "🚀"),
            (["운동", "사이클", "러닝", "헬스", "체력"], "🏃"),
            (["논문", "공부", "학습", "강의", "리서치"], "📚"),
            (["정리", "문서", "설계", "기획", "회고"], "📝"),
        ]

        return keywordGroups.compactMap { group in
            let items = goals.filter { goal in
                group.keywords.contains { keyword in
                    goal.title.localizedCaseInsensitiveContains(keyword)
                        || goal.rule.localizedCaseInsensitiveContains(keyword)
                }
            }
            guard items.count >= 2 else { return nil }
            let limited = limitedGoals(items)
            return monthlySuggestion(
                title: monthlyTitle(for: limited),
                reason: "비슷한 방향의 주간 목표 \(limited.count)개를 한 달 목표로 묶었습니다.",
                goals: limited,
                emoji: group.emoji,
                source: .rule
            )
        }
    }

    private static func groupedMonthlyFallback(from goals: [AchievementGoalSnapshot]) -> [AchievementGoalSuggestion] {
        guard goals.count >= 2 else { return [] }
        let limited = limitedGoals(goals)
        return [
            monthlySuggestion(
                title: monthlyTitle(for: limited),
                reason: "이번 달에 함께 밀어야 할 주간 목표 \(limited.count)개를 묶었습니다.",
                goals: limited,
                emoji: "📅",
                source: .rule
            ),
        ]
    }

    private static func monthlySuggestion(
        title: String,
        reason: String,
        goals: [AchievementGoalSnapshot],
        emoji: String,
        source: AchievementGoalSuggestionSource
    ) -> AchievementGoalSuggestion {
        let count = goals.count
        let memoIDs = Array(Set(goals.flatMap(\.sourceMemoIDs)))
        return AchievementGoalSuggestion(
            title: title,
            reason: reason,
            memoIDs: memoIDs,
            childGoalIDs: goals.map(\.id),
            scheduleText: "이번 달에 주간 목표 \(count)개로 나눠 진행",
            criterion: "연결한 주간 목표 \(count)개 달성",
            targetValueText: "\(count)개",
            emoji: emoji,
            target: .monthly,
            source: source
        )
    }

    private static func limitedGoals(_ goals: [AchievementGoalSnapshot]) -> [AchievementGoalSnapshot] {
        Array(goals.sorted { lhs, rhs in
            if lhs.done == lhs.total, rhs.done != rhs.total {
                return false
            }
            if lhs.done != lhs.total, rhs.done == rhs.total {
                return true
            }
            if lhs.total == rhs.total {
                return lhs.title < rhs.title
            }
            return lhs.total > rhs.total
        }.prefix(4))
    }

    private static func deduplicated(_ suggestions: [AchievementGoalSuggestion]) -> [AchievementGoalSuggestion] {
        var seen = Set<Set<UUID>>()
        var result: [AchievementGoalSuggestion] = []
        for suggestion in suggestions where suggestion.memoIDs.count >= 2 {
            let key = Set(suggestion.memoIDs)
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
        }
        return result
    }

    private static func deduplicatedMonthly(_ suggestions: [AchievementGoalSuggestion]) -> [AchievementGoalSuggestion] {
        var seen = Set<Set<UUID>>()
        var result: [AchievementGoalSuggestion] = []
        for suggestion in suggestions where suggestion.childGoalIDs.count >= 2 {
            let key = Set(suggestion.childGoalIDs)
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
        }
        return result
    }
}

private struct AchievementFoundationSuggestionPayload: Codable {
    let suggestions: [Item]

    struct Item: Codable {
        let title: String
        let reason: String
        let memoIDs: [String]?
        let goalIDs: [String]?
        let scheduleText: String
        let criterion: String
        let emoji: String?
    }
}

private enum AchievementFoundationGoalSuggestionProvider {
    static func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) async -> [AchievementGoalSuggestion] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelsGoalSuggestionProvider().suggestions(
                from: memos,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            )
        }
        #endif
        return []
    }

    static func monthlySuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int
    ) async -> [AchievementGoalSuggestion] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await FoundationModelsGoalSuggestionProvider().monthlySuggestions(
                from: goals,
                suggestionCount: suggestionCount
            )
        }
        #endif
        return []
    }
}

private enum AchievementPromptTemplate {
    static func weeklyGoalSuggestion(
        suggestionCount: Int,
        maxMemoCount: Int,
        items: String
    ) -> String {
        render(
            fileName: "achievement_weekly_goal_suggestion",
            fallback: weeklyGoalSuggestionFallback,
            values: [
                "suggestionCount": "\(suggestionCount)",
                "maxMemoCount": "\(maxMemoCount)",
                "items": items,
            ]
        )
    }

    static func monthlyGoalSuggestion(
        suggestionCount: Int,
        items: String
    ) -> String {
        render(
            fileName: "achievement_monthly_goal_suggestion",
            fallback: monthlyGoalSuggestionFallback,
            values: [
                "suggestionCount": "\(suggestionCount)",
                "items": items,
            ]
        )
    }

    private static func render(
        fileName: String,
        fallback: String,
        values: [String: String]
    ) -> String {
        var result = load(fileName: fileName) ?? fallback
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    private static func load(fileName: String) -> String? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static let weeklyGoalSuggestionFallback = """
    아래 할일들을 의미, 아이콘, 시작일, 마감일, 완료 상태를 함께 보고 주간 목표 후보를 최대 {{suggestionCount}}개 제안해줘.
    목표 후보 하나에는 할일을 최대 {{maxMemoCount}}개까지만 넣어.
    각 후보는 사용자가 수정할 수 있는 초안이어야 하고, 같은 할일을 여러 후보에 중복해서 넣지 마.
    존재하는 id만 memoIDs에 넣어.
    scheduleText는 실제 startDate, deadline, date를 고려해 짧게 작성해.

    JSON 형식:
    {
      "suggestions": [
        {
          "title": "목표명",
          "reason": "묶은 이유",
          "memoIDs": ["UUID"],
          "scheduleText": "월/수/금에 나눠 진행",
          "criterion": "연결한 할일 3개 완료",
          "emoji": "🎯"
        }
      ]
    }

    할일:
    {{items}}
    """

    private static let monthlyGoalSuggestionFallback = """
    아래 주간 목표들을 의미, 달성 기준, 페르소나, 비전, 연결된 할일 수를 함께 보고 월간 목표 후보를 최대 {{suggestionCount}}개 제안해줘.
    월간 목표 하나에는 주간 목표를 2개 이상 4개 이하로 넣어.
    title은 입력된 주간 목표들의 실제 내용에서만 추론해 새로 작성해.
    입력에 없는 구체적인 숫자, 회사 수, 횟수, 마감 조건은 만들지 마.
    같은 주간 목표를 여러 월간 후보에 중복해서 넣지 마.
    존재하는 id만 goalIDs에 넣어.

    JSON 형식:
    {
      "suggestions": [
        {
          "title": "월간 목표명",
          "reason": "묶은 이유",
          "goalIDs": ["UUID"],
          "scheduleText": "이번 달에 주간 목표 3개로 나눠 진행",
          "criterion": "연결한 주간 목표 3개 달성",
          "emoji": "📅"
        }
      ]
    }

    주간 목표:
    {{items}}
    """
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct FoundationModelsGoalSuggestionProvider {
    func suggestions(
        from memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) async -> [AchievementGoalSuggestion] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return [] }

        let session = LanguageModelSession(
            model: model,
            instructions: "너는 사용자의 할일을 목표 지향적으로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다."
        )
        let inputLimit = max(8, min(40, suggestionCount * maxMemoCount * 2))
        let prompt = prompt(
            for: Array(memos.prefix(inputLimit)),
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount
        )

        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 900)
            )
            return Array(parse(
                response.content,
                allowedIDs: Set(memos.map(\.id)),
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            ).prefix(suggestionCount))
        } catch {
            return []
        }
    }

    func monthlySuggestions(
        from goals: [AchievementGoalSnapshot],
        suggestionCount: Int
    ) async -> [AchievementGoalSuggestion] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return [] }

        let session = LanguageModelSession(
            model: model,
            instructions: "너는 사용자의 주간 목표를 더 큰 월간 목표로 묶어주는 생산성 앱 도우미다. 응답은 반드시 유효한 JSON만 출력한다."
        )
        let inputLimit = max(3, min(30, suggestionCount * 6))
        let prompt = monthlyPrompt(
            for: Array(goals.prefix(inputLimit)),
            suggestionCount: suggestionCount
        )

        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.25, maximumResponseTokens: 900)
            )
            return Array(parseMonthly(
                response.content,
                allowedIDs: Set(goals.map(\.id)),
                sourceGoals: goals,
                suggestionCount: suggestionCount
            ).prefix(suggestionCount))
        } catch {
            return []
        }
    }

    private func prompt(
        for memos: [AchievementMemoSnapshot],
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> String {
        let lines = memos.map { memo in
            let startText = dateText(memo.startDate)
            let deadlineText = dateText(memo.deadline)
            let representativeDateText = dateText(memo.date)
            return [
                "- id: \(memo.id.uuidString)",
                "  text: \(memo.content)",
                "  icon: \(memo.icon ?? MemoIcon.defaultIcon)",
                "  date: \(representativeDateText)",
                "  startDate: \(startText)",
                "  deadline: \(deadlineText)",
                "  completed: \(memo.isCompleted ? "true" : "false")",
            ].joined(separator: "\n")
        }.joined(separator: "\n")

        return AchievementPromptTemplate.weeklyGoalSuggestion(
            suggestionCount: suggestionCount,
            maxMemoCount: maxMemoCount,
            items: lines
        )
    }

    private func monthlyPrompt(
        for goals: [AchievementGoalSnapshot],
        suggestionCount: Int
    ) -> String {
        let lines = goals.map { goal in
            [
                "- id: \(goal.id.uuidString)",
                "  title: \(goal.title)",
                "  emoji: \(goal.emoji)",
                "  rule: \(goal.rule)",
                "  progress: \(goal.done)/\(goal.total)",
                "  role: \(goal.roleName.isEmpty ? "없음" : goal.roleName)",
                "  vision: \(goal.vision.isEmpty ? "없음" : goal.vision)",
                "  linkedTodoCount: \(goal.sourceMemoIDs.count)",
            ].joined(separator: "\n")
        }.joined(separator: "\n")

        return AchievementPromptTemplate.monthlyGoalSuggestion(
            suggestionCount: suggestionCount,
            items: lines
        )
    }

    private func parse(
        _ text: String,
        allowedIDs: Set<UUID>,
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> [AchievementGoalSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: trimmed)
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AchievementFoundationSuggestionPayload.self, from: data) else {
            return []
        }

        var used = Set<UUID>()
        return payload.suggestions.compactMap { item in
            let ids = (item.memoIDs ?? []).compactMap(UUID.init(uuidString:))
                .filter { allowedIDs.contains($0) && !used.contains($0) }
                .prefix(maxMemoCount)
            guard ids.count >= 2 else { return nil }
            used.formUnion(ids)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let criterion = item.criterion.trimmingCharacters(in: .whitespacesAndNewlines)
            return AchievementGoalSuggestion(
                title: title.isEmpty ? "추천 목표" : title,
                reason: AchievementDataBuilder.shortText(item.reason, limit: 72),
                memoIDs: Array(ids),
                scheduleText: item.scheduleText.isEmpty ? "이번 주에 나눠 진행" : item.scheduleText,
                criterion: criterion.isEmpty ? "연결한 할일 \(ids.count)개 완료" : criterion,
                targetValueText: "\(ids.count)개",
                emoji: item.emoji?.isEmpty == false ? String(item.emoji!.prefix(1)) : "🎯",
                source: .foundationModel
            )
        }
        .prefix(suggestionCount)
        .map { $0 }
    }

    private func parseMonthly(
        _ text: String,
        allowedIDs: Set<UUID>,
        sourceGoals: [AchievementGoalSnapshot],
        suggestionCount: Int
    ) -> [AchievementGoalSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = extractJSONObject(from: trimmed)
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AchievementFoundationSuggestionPayload.self, from: data) else {
            return []
        }

        let goalByID = Dictionary(uniqueKeysWithValues: sourceGoals.map { ($0.id, $0) })
        var used = Set<UUID>()
        return payload.suggestions.compactMap { item in
            let ids = (item.goalIDs ?? []).compactMap(UUID.init(uuidString:))
                .filter { allowedIDs.contains($0) && !used.contains($0) }
                .prefix(4)
            guard ids.count >= 2 else { return nil }
            used.formUnion(ids)
            let goals = ids.compactMap { goalByID[$0] }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let criterion = item.criterion.trimmingCharacters(in: .whitespacesAndNewlines)
            let scheduleText = item.scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
            return AchievementGoalSuggestion(
                title: title.isEmpty ? "추천 월간 목표" : title,
                reason: AchievementDataBuilder.shortText(item.reason, limit: 72),
                memoIDs: Array(Set(goals.flatMap(\.sourceMemoIDs))),
                childGoalIDs: Array(ids),
                scheduleText: scheduleText.isEmpty ? "이번 달에 주간 목표 \(ids.count)개로 나눠 진행" : scheduleText,
                criterion: criterion.isEmpty ? "연결한 주간 목표 \(ids.count)개 달성" : criterion,
                targetValueText: "\(ids.count)개",
                emoji: item.emoji?.isEmpty == false ? String(item.emoji!.prefix(1)) : "📅",
                target: .monthly,
                source: .foundationModel
            )
        }
        .prefix(suggestionCount)
        .map { $0 }
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd E HH:mm"
        return formatter.string(from: date)
    }
}
#endif

private enum AchievementDataBuilder {
    static func goals(from records: [AchievementGoalRecord], memos: [Memo]) -> [AchievementGoal] {
        let memoByID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
        func nonEmpty(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        func childCadence(for cadence: String) -> String? {
            switch cadence {
            case "연간": return "월간"
            case "월간": return "주간"
            default: return nil
            }
        }
        func childRecords(for record: AchievementGoalRecord) -> [AchievementGoalRecord] {
            guard let childCadence = childCadence(for: record.cadence) else { return [] }
            return records.filter { child in
                guard child.cadence == childCadence else { return false }
                switch record.cadence {
                case "연간":
                    return nonEmpty(child.yearGoal) == record.title
                case "월간":
                    return nonEmpty(child.monthGoal) == record.title
                default:
                    return false
                }
            }
        }
        func directProgress(for record: AchievementGoalRecord) -> (done: Int, total: Int) {
            let linkedMemos = record.linkedMemoIDs.compactMap { memoByID[$0] }
            guard !linkedMemos.isEmpty else { return (0, 0) }
            return (linkedMemos.filter(\.isCompletedValue).count, max(1, record.targetCount))
        }
        func progress(for record: AchievementGoalRecord, visited: Set<UUID> = []) -> (done: Int, total: Int) {
            guard !visited.contains(record.id) else {
                return directProgress(for: record)
            }
            let children = childRecords(for: record)
            guard !children.isEmpty else {
                return directProgress(for: record)
            }
            let nextVisited = visited.union([record.id])
            let childProgresses = children.map { progress(for: $0, visited: nextVisited) }
            let completedChildren = childProgresses.filter { $0.total > 0 && $0.done >= $0.total }.count
            return (completedChildren, children.count)
        }
        func descendantMemoIDs(for record: AchievementGoalRecord, visited: Set<UUID> = []) -> [UUID] {
            guard !visited.contains(record.id) else {
                return record.linkedMemoIDs
            }
            let nextVisited = visited.union([record.id])
            let childMemoIDs = childRecords(for: record).flatMap { descendantMemoIDs(for: $0, visited: nextVisited) }
            return Array(Set(record.linkedMemoIDs + childMemoIDs))
        }
        return records.map { record in
            let sourceMemoIDs = descendantMemoIDs(for: record)
            let linkedMemos = sourceMemoIDs.compactMap { memoByID[$0] }
                .sorted { memoDate($0) < memoDate($1) }
            let recordDate = linkedMemos
                .filter(\.isCompletedValue)
                .map(memoDate)
                .max() ?? record.updatedAt
            let todos = linkedMemos.map { memo in
                AchievementTodo(
                    id: memo.id,
                    text: shortText(memo.content, limit: 28),
                    when: dateRangeText(for: memo),
                    detail: todoDetail(for: memo),
                    status: todoStatus(for: memo)
                )
            }
            let goalProgress = progress(for: record)
            let done = goalProgress.total > 0 ? min(goalProgress.done, goalProgress.total) : 0
            let total = goalProgress.total
            let rewardStatus: AchievementRewardStatus = total > 0 && done >= total ? .earned : .pending
            return AchievementGoal(
                id: record.id,
                emoji: record.emoji,
                title: shortText(record.title, limit: 40),
                cadence: record.cadence,
                rule: displayRule(for: record, total: total),
                done: min(done, total),
                total: total,
                reward: AchievementReward(amount: record.rewardText.isEmpty ? "보상 없음" : record.rewardText, status: rewardStatus),
                color: color(from: record.colorHex),
                todos: todos,
                roleName: record.roleName,
                vision: record.vision,
                yearGoal: record.yearGoal,
                quarterGoal: record.quarterGoal,
                monthGoal: record.monthGoal,
                recordDate: recordDate,
                sourceMemoIDs: sourceMemoIDs
            )
        }
    }

    static func roles(from goals: [AchievementGoal]) -> [AchievementRole] {
        var seen = Set<String>()
        let personaNames = Set(goals.filter { $0.cadence == "역할" }.map(\.title))
        return goals.compactMap { goal in
            guard !goal.roleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            guard personaNames.contains(goal.roleName) else {
                return nil
            }
            guard seen.insert(goal.roleName).inserted else { return nil }
            let personaGoal = goals.first { $0.cadence == "역할" && $0.title == goal.roleName }
            let roleGoals = goals.filter { $0.roleName == goal.roleName }
            let visionGoal = roleGoals.first { $0.cadence == "비전" }
            let roleVision = [
                visionGoal?.vision,
                visionGoal?.title,
                roleGoals.first { !$0.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.vision,
                goal.vision,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
            return AchievementRole(id: goal.roleName, emoji: personaGoal?.emoji ?? goal.emoji, name: goal.roleName, vision: roleVision)
        }
    }

    static func timeline(for goal: AchievementGoal, memos: [Memo], referenceDate: Date = Date()) -> [AchievementTimelineItem] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let weekdayOffsetFromMonday = (calendar.component(.weekday, from: todayStart) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -weekdayOffsetFromMonday, to: todayStart) ?? todayStart
        let linked = memos.filter { goal.sourceMemoIDs.contains($0.id) }
        let completedCount = linked.filter(\.isCompletedValue).count
        let lastCompletedDate = linked.filter(\.isCompletedValue).compactMap(timelineDate).max()

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let dayMemos = linked
                .filter { memo in
                    guard let date = timelineDate(memo) else { return false }
                    return calendar.isDate(date, inSameDayAs: day)
                }
                .sorted {
                    (timelineDate($0) ?? .distantFuture) < (timelineDate($1) ?? .distantFuture)
                }
            let isLastDay = offset == 6
            let hasReward = isLastDay && !goal.reward.amount.isEmpty && goal.reward.amount != "보상 없음"
            let isCompletedDay = dayMemos.contains(where: \.isCompletedValue)
            let isFutureDay = !isCompletedDay && calendar.startOfDay(for: day) > calendar.startOfDay(for: referenceDate)
            let topLabel: String?
            if hasReward {
                topLabel = goal.reward.amount
            } else if let lastCompletedDate, calendar.isDate(lastCompletedDate, inSameDayAs: day) {
                topLabel = "\(min(completedCount, goal.total))/\(goal.total) 달성"
            } else {
                topLabel = nil
            }
            return AchievementTimelineItem(
                date: day,
                weekday: weekday(day),
                topLabel: topLabel,
                todos: dayMemos.map { memo in
                    AchievementTimelineTodo(
                        id: memo.id,
                        memoID: memo.id,
                        title: shortText(memo.content, limit: 15),
                        meta: todoMetaText(for: memo),
                        isCompleted: memo.isCompletedValue,
                        isFuture: todoStatus(for: memo, referenceDate: referenceDate) == .future
                    )
                },
                isCompleted: isCompletedDay || hasReward,
                isFuture: isFutureDay,
                isReward: hasReward
            )
        }
    }

    static func timeline(for goals: [AchievementGoal], memos: [Memo], referenceDate: Date = Date()) -> [AchievementTimelineItem] {
        guard !goals.isEmpty else { return [] }

        let timelines = goals.map { goal in
            (goal: goal, items: timeline(for: goal, memos: memos, referenceDate: referenceDate))
        }

        return (0..<7).map { index in
            let dayItems = timelines.compactMap { timeline in
                timeline.items.indices.contains(index) ? (timeline.goal, timeline.items[index]) : nil
            }
            let baseItem = dayItems.first?.1
            let todos = dayItems.flatMap { goal, item in
                item.todos.map { todo in
                    AchievementTimelineTodo(
                        id: UUID(),
                        memoID: todo.memoID,
                        title: "\(goal.emoji) \(todo.title)",
                        meta: todo.meta,
                        isCompleted: todo.isCompleted,
                        isFuture: todo.isFuture
                    )
                }
            }

            return AchievementTimelineItem(
                date: baseItem?.date ?? Date(),
                weekday: baseItem?.weekday ?? "",
                topLabel: nil,
                todos: todos,
                isCompleted: dayItems.contains { $0.1.isCompleted },
                isFuture: !dayItems.contains { $0.1.isCompleted } && (baseItem?.isFuture ?? false),
                isReward: false
            )
        }
    }

    static func activeMemos(_ memos: [Memo]) -> [Memo] {
        memos.filter { !$0.isArchivedValue }
    }

    static func displayRule(for record: AchievementGoalRecord, total: Int) -> String {
        let criterion = record.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if !criterion.isEmpty {
            return criterion
        }
        let target = record.targetValueText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = record.periodText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            target?.isEmpty == false ? target : (total > 0 ? "메모 \(total)개 완료" : nil),
            period?.isEmpty == false ? period : record.cadence,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    static func memoDate(_ memo: Memo) -> Date {
        memo.deadline ?? memo.startDate ?? memo.updatedAt
    }

    private static func timelineDate(_ memo: Memo) -> Date? {
        memo.deadline ?? memo.startDate
    }

    static func dateRangeText(for memo: Memo) -> String {
        switch (memo.startDate, memo.deadline) {
        case let (start?, deadline?):
            return "\(shortDate(start)) - \(shortDate(deadline))"
        case let (start?, nil):
            return "시작 \(shortDate(start))"
        case let (nil, deadline?):
            return "마감 \(shortDate(deadline))"
        default:
            return ""
        }
    }

    static func todoMetaText(for memo: Memo) -> String {
        let dateText = dateRangeText(for: memo)
        let detail = todoDetail(for: memo)
        if dateText.isEmpty {
            return detail
        }
        if detail.isEmpty {
            return dateText
        }
        return "\(dateText) · \(detail)"
    }

    static func todoDetail(for memo: Memo, referenceDate: Date = Date()) -> String {
        if memo.isCompletedValue {
            return "완료"
        }
        guard memo.startDate != nil || memo.deadline != nil else {
            return ""
        }
        if Calendar.current.startOfDay(for: memoDate(memo)) > Calendar.current.startOfDay(for: referenceDate) {
            return "예정"
        }
        return ""
    }

    static func todoStatus(for memo: Memo, referenceDate: Date = Date()) -> AchievementTodoStatus {
        if memo.isCompletedValue {
            return .done
        }
        if Calendar.current.startOfDay(for: memoDate(memo)) > Calendar.current.startOfDay(for: referenceDate) {
            return .future
        }
        return .pending
    }

    static func shortText(_ value: String, limit: Int) -> String {
        let trimmed = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return "\(trimmed.prefix(limit))..."
    }

    static func color(from hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return PopoverChrome.accent
        }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E HH:mm"
        return formatter.string(from: date)
    }

    private static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

struct AchievementSummaryView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Memo.updatedAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \AchievementGoalRecord.updatedAt, order: .reverse) private var goalRecords: [AchievementGoalRecord]
    @State private var hostWindow: NSWindow?

    private let textScale: CGFloat = 0.8

    private var goals: [AchievementGoal] {
        AchievementDataBuilder.goals(from: goalRecords, memos: memos)
    }

    private var weeklyGoals: [AchievementGoal] {
        goals.filter { $0.cadence == "주간" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(showsIndicators: true) {
                VStack(spacing: 12) {
                    if weeklyGoals.isEmpty {
                        emptyGoalState
                    } else {
                        ForEach(weeklyGoals) { goal in
                            AchievementGoalSummaryCard(goal: goal, textScale: textScale)
                        }
                    }

                    addGoalButton
                }
                .padding(.trailing, 7)
                .padding(.bottom, 4)
            }
            .popoverScrollbar()
        }
        .configureHostWindow { window in
            hostWindow = window
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: "target")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("이번 주 성취")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                }
                Spacer()
                detailButton(label: "성취 상세")
            }

            Text("목표 \(completedGoalCount)/\(weeklyGoals.count) 달성 · 연결된 메모 \(linkedMemoCount)개")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(.bottom, 2)
    }

    private var emptyGoalState: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
            Text("아직 등록된 성취 목표가 없습니다")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Text("메모장에서 만든 할일을 선택해 목표로 묶을 수 있어요.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .popoverCard(padding: 14, radius: 14)
    }

    private var addGoalButton: some View {
        Button {
            openGoalComposer()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("메모로 목표 추가")
            }
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(PopoverChrome.surfaceAlt.opacity(0.78), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var completedGoalCount: Int {
        weeklyGoals.filter(\.isComplete).count
    }

    private var linkedMemoCount: Int {
        Set(weeklyGoals.flatMap(\.sourceMemoIDs)).count
    }

    private func detailButton(label: String) -> some View {
        Button {
            openAchievementDetail()
        } label: {
            HStack(spacing: 3) {
                Text(label)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7.5, weight: .bold))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    private func openAchievementDetail() {
        let popoverWindow = hostWindow
        openWindow(id: "achievement-detail")
        popoverWindow?.orderOut(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "achievement-detail" || $0.title == "호롱호롱 성취"
            }) {
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private func openGoalComposer() {
        AchievementDetailLaunchOptions.shared.shouldOpenGoalComposer = true
        openAchievementDetail()
    }
}

@MainActor
@Observable
final class AchievementDetailLaunchOptions {
    static let shared = AchievementDetailLaunchOptions()
    var shouldOpenGoalComposer = false

    private init() {}

    func consumeGoalComposerRequest() -> Bool {
        guard shouldOpenGoalComposer else { return false }
        shouldOpenGoalComposer = false
        return true
    }
}

private struct AchievementGoalSummaryCard: View {
    let goal: AchievementGoal
    var textScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Text(goal.emoji)
                    .font(.system(size: 22))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(.system(size: scaled(16), weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(goal.cadence) · \(goal.rule)")
                        .font(.system(size: scaled(12), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)
                AchievementRewardBadge(reward: goal.reward, color: goal.color, textScale: textScale)
            }

            HStack(spacing: 10) {
                AchievementProgressBar(progress: goal.progress, color: goal.color)
                Text("\(goal.done)/\(goal.total)")
                    .font(.system(size: scaled(14), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
            }

            if let todo = goal.nextTodo {
                Divider()
                    .overlay(PopoverChrome.divider)
                HStack(spacing: 8) {
                    Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: scaled(15), weight: .bold))
                        .foregroundStyle(todo.status == .done ? goal.color : PopoverChrome.inkTertiary)
                    Text(todo.status == .done ? "최근 증거 · \(todo.text)" : "다음 할일 · \(todo.text)")
                        .font(.system(size: scaled(12.5), weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if !todo.metaText.isEmpty {
                        Text(todo.metaText)
                            .font(.system(size: scaled(11), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .popoverCard(padding: 13, radius: 14)
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        size * textScale
    }
}

private struct AchievementRewardBadge: View {
    let reward: AchievementReward
    let color: Color
    var textScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gift")
                .font(.system(size: 10 * textScale, weight: .bold))
            Text("\(reward.amount) \(reward.status.label)")
                .font(.system(size: 11.5 * textScale, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AchievementProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PopoverChrome.surfaceAlt)
                Capsule()
                    .fill(color)
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 9)
    }
}

struct AchievementDetailScreenshotState {
    let tabIdentifier: String
    let weekGoalFilterIdentifier: String?

    init(tabIdentifier: String, weekGoalFilterIdentifier: String? = nil) {
        self.tabIdentifier = tabIdentifier
        self.weekGoalFilterIdentifier = weekGoalFilterIdentifier
    }
}

private enum AchievementDetailTab: String, CaseIterable, Identifiable {
    case progress = "진행"
    case journey = "여정"
    case records = "달성 기록"

    var id: String { rawValue }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "progress":
            self = .progress
        case "journey":
            self = .journey
        case "records":
            self = .records
        default:
            return nil
        }
    }
}

private enum AchievementPeriod: String, CaseIterable, Identifiable {
    case week = "주간"
    case month = "월간"

    var id: String { rawValue }
}

private enum AchievementWeekGoalFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case goal = "목표별"
    case reward = "보상만"

    var id: String { rawValue }

    init?(screenshotIdentifier: String) {
        switch screenshotIdentifier.lowercased() {
        case "all":
            self = .all
        case "goal":
            self = .goal
        case "reward":
            self = .reward
        default:
            return nil
        }
    }
}

private enum AchievementRecordScope: String, CaseIterable, Identifiable {
    case all = "전체"
    case weekly = "주간"
    case monthly = "월간"

    var id: String { rawValue }
}

private struct AchievementRecordMonthGroup: Identifiable {
    let id: String
    let title: String
    let goals: [AchievementGoal]
}

struct AchievementDetailWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memo.updatedAt, order: .reverse) private var memos: [Memo]
    @Query(sort: \AchievementGoalRecord.updatedAt, order: .reverse) private var goalRecords: [AchievementGoalRecord]
    @AppStorage(Constants.AppStorageKey.achievementJourneyMaxFlagCount)
    private var journeyMaxFlagCount: Int = Constants.defaultAchievementJourneyMaxFlagCount
    @State private var launchOptions = AchievementDetailLaunchOptions.shared
    @State private var selectedTab: AchievementDetailTab = .progress
    @State private var selectedPeriod: AchievementPeriod = .week
    @State private var displayedMonth = Date()
    @State private var selectedGoalID: UUID?
    @State private var selectedWeekGoalFilter: AchievementWeekGoalFilter = .goal
    @State private var selectedRecordScope: AchievementRecordScope = .all
    @State private var selectedRoleID = ""
    @State private var showGoalComposer = false
    @State private var managingGoalID: UUID?
    @State private var overdueRescheduleMessage = ""
    @State private var journeyImageRefreshID = UUID()
    @State private var showsJourneyImageOptions = false
    @State private var showsJourneyVisionOptions = false
    @State private var showPersonaVisionComposer = false
    @State private var selectedJourneyVisionID: UUID?
    @State private var selectedJourneyFlagIndex: Int?
    @State private var journeyFlagRefreshID = UUID()

    init(initialScreenshotState: AchievementDetailScreenshotState? = nil) {
        if let tabIdentifier = initialScreenshotState?.tabIdentifier,
           let tab = AchievementDetailTab(screenshotIdentifier: tabIdentifier) {
            _selectedTab = State(initialValue: tab)
        }
        if let filterIdentifier = initialScreenshotState?.weekGoalFilterIdentifier,
           let filter = AchievementWeekGoalFilter(screenshotIdentifier: filterIdentifier) {
            _selectedWeekGoalFilter = State(initialValue: filter)
        }
    }

    private var goals: [AchievementGoal] {
        AchievementDataBuilder.goals(from: goalRecords, memos: memos)
    }

    private var roles: [AchievementRole] {
        AchievementDataBuilder.roles(from: goals)
    }

    private var selectedGoal: AchievementGoal? {
        if let selectedGoalID, let goal = goals.first(where: { $0.id == selectedGoalID }) {
            return goal
        }
        return goals.first
    }

    private var managingGoalRecord: AchievementGoalRecord? {
        guard let managingGoalID else { return nil }
        return goalRecords.first { $0.id == managingGoalID }
    }

    private var selectedWeekGoal: AchievementGoal? {
        if let selectedGoalID, let goal = weeklyGoals.first(where: { $0.id == selectedGoalID }) {
            return goal
        }
        return weeklyGoals.first
    }

    private var visibleWeeklyGoals: [AchievementGoal] {
        switch selectedWeekGoalFilter {
        case .all:
            return weeklyGoals
        case .goal:
            return selectedWeekGoal.map { [$0] } ?? []
        case .reward:
            return weeklyGoals.filter { $0.reward.status == .pending }
        }
    }

    private var weeklyTimelineTitle: String {
        switch selectedWeekGoalFilter {
        case .all:
            return "전체 주간 목표 흐름"
        case .goal:
            return selectedWeekGoal.map { "\($0.title) 흐름" } ?? "주간 목표 흐름"
        case .reward:
            return "보상 대기 목표 흐름"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch selectedTab {
                        case .progress:
                            progressHeader
                            periodContent
                        case .records:
                            recordsContent
                        case .journey:
                            journeyContent
                        }
                    }
                    .padding(18)
                }
                .background(PopoverChrome.surface)
                .disabled(showGoalComposer)

                if showGoalComposer {
                    Color.white.opacity(0.24)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeGoalComposer()
                        }
                        .transition(.opacity)

                    AchievementGoalComposerSheet(
                        memos: AchievementDataBuilder.activeMemos(memos),
                        existingGoals: goals,
                        onClose: closeGoalComposer
                    ) { record, childGoalIDs in
                        modelContext.insert(record)
                        connectChildGoals(childGoalIDs, to: record)
                        try modelContext.save()
                        selectedGoalID = record.id
                        selectedRoleID = record.roleName
                    }
                    .frame(maxHeight: .infinity)
                    .shadow(color: Color.black.opacity(0.16), radius: 22, x: -10, y: 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(PopoverChrome.surface)
        .sheet(isPresented: Binding(get: { managingGoalID != nil }, set: { isPresented in
            if !isPresented {
                managingGoalID = nil
            }
        })) {
            if let managingGoalRecord {
                AchievementGoalManagementSheet(
                    record: managingGoalRecord,
                    linkedMemoCount: managingGoalRecord.linkedMemoIDs.count,
                    memos: linkableMemos(for: managingGoalRecord),
                    childRecords: childRecords(for: managingGoalRecord),
                    childCadence: childCadence(for: managingGoalRecord.cadence),
                    onSave: updateGoalRecord,
                    onDelete: deleteGoalRecord,
                    onAddChild: addChildGoal,
                    onUpdateChild: updateChildGoal,
                    onDeleteChild: deleteGoalRecord
                )
            } else {
                AchievementEmptyDetailCard(message: "관리할 목표를 찾을 수 없습니다.")
                    .frame(width: 360, height: 160)
                .padding()
            }
        }
        .sheet(isPresented: $showPersonaVisionComposer) {
            AchievementPersonaVisionComposerSheet(
                personas: roles,
                selectedPersonaID: selectedRoleID,
                onClose: {
                    showPersonaVisionComposer = false
                },
                onSave: savePersonaVisionDraft
            )
        }
        .onAppear {
            ensureSelection()
            if launchOptions.consumeGoalComposerRequest() {
                openGoalComposer()
            }
        }
        .onChange(of: goalRecords.count) { _, _ in
            ensureSelection()
        }
        .onChange(of: launchOptions.shouldOpenGoalComposer) { _, shouldOpen in
            if shouldOpen, launchOptions.consumeGoalComposerRequest() {
                openGoalComposer()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showGoalComposer)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            AchievementSegmentedPicker(selection: $selectedTab, values: AchievementDetailTab.allCases)
            Spacer()
            Button {
                openGoalComposer()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("목표")
                }
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accentInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PopoverChrome.surfaceAlt)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private func openGoalComposer() {
        showGoalComposer = true
    }

    private func closeGoalComposer() {
        showGoalComposer = false
    }

    private var progressHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedPeriod == .week ? "이번 주 목표" : "월간 목표")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("진행 중인 목표와 연결된 할일을 관리합니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            Spacer(minLength: 10)

            Menu {
                ForEach(AchievementPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Label(
                            period.rawValue,
                            systemImage: selectedPeriod == period ? "checkmark" : period == .week ? "calendar.badge.clock" : "calendar"
                        )
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: selectedPeriod == .week ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 11.5, weight: .bold))
                    Text(selectedPeriod.rawValue)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var periodContent: some View {
        switch selectedPeriod {
        case .week:
            weekContent
        case .month:
            monthContent
        }
    }

    private var weekContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                AchievementMetricCard(label: "이번 주 성취", value: "\(completedWeeklyGoalCount)/\(weeklyGoals.count)", icon: "target")
                AchievementMetricCard(label: "지급 대기", value: "\(weeklyPendingRewardCount)", icon: "gift")
                AchievementMetricCard(label: "연결된 메모", value: "\(weeklyLinkedMemoCount)", icon: "checkmark.seal")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("성취 타임라인")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text(weeklyTimelineTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }
                    Spacer()
                    if let selectedWeekGoal {
                        AchievementTimelineFilters(
                            goals: weeklyGoals,
                            selectedGoalID: $selectedGoalID,
                            selectedFilter: $selectedWeekGoalFilter,
                            selectedGoal: selectedWeekGoal
                        )
                    }
                }

                if !visibleWeeklyGoals.isEmpty {
                    overdueMemosBanner
                    AchievementGoalTimelineView(
                        items: AchievementDataBuilder.timeline(for: visibleWeeklyGoals, memos: memos),
                        onMoveTodo: moveTimelineMemo
                    )
                } else {
                    AchievementEmptyDetailCard(message: "주간 목표를 추가하면 타임라인이 표시됩니다.")
                }
            }
            .achievementDetailCard()

            if weeklyGoals.isEmpty {
                AchievementEmptyDetailCard(message: "이번 주에 표시할 주간 목표가 없습니다.")
            } else if visibleWeeklyGoals.isEmpty {
                AchievementEmptyDetailCard(message: "조건에 맞는 주간 목표가 없습니다.")
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleWeeklyGoals) { goal in
                        AchievementDetailGoalRow(
                            goal: goal,
                            onAdd: {
                                manageGoal(goal)
                            },
                            onManage: {
                                manageGoal(goal)
                            },
                            onDelete: {
                            deleteGoal(goal)
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overdueMemosBanner: some View {
        let overdueMemos = overdueVisibleWeeklyMemos
        if !overdueMemos.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PopoverChrome.accent)
                        .frame(width: 30, height: 30)
                        .background(PopoverChrome.accentSoft.opacity(0.72), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("지난 일정의 미완료 할일 \(overdueMemos.count)개")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text(overdueMemosPreview(overdueMemos))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 7) {
                        Button {
                            moveOverdueMemosToToday(overdueMemos)
                        } label: {
                            Text("오늘로 이동")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            distributeOverdueMemosAcrossRemainingWeek(overdueMemos)
                        } label: {
                            Text("남은 요일에 나누기")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.accentInk)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !overdueRescheduleMessage.isEmpty {
                    Text(overdueRescheduleMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.70), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                    .stroke(PopoverChrome.accent.opacity(0.22), lineWidth: PopoverChrome.borderWidth)
            )
        } else if !overdueRescheduleMessage.isEmpty {
            Text(overdueRescheduleMessage)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .onAppear {
                    clearOverdueRescheduleMessageLater()
                }
        }
    }

    private var overdueVisibleWeeklyMemos: [Memo] {
        let sourceIDs = Set(visibleWeeklyGoals.flatMap(\.sourceMemoIDs))
        let weekStart = currentWeekStart
        return memos
            .filter { memo in
                sourceIDs.contains(memo.id)
                    && !memo.isCompletedValue
                    && !memo.isArchivedValue
                    && (memo.startDate != nil || memo.deadline != nil)
                    && AchievementDataBuilder.memoDate(memo) < weekStart
            }
            .sorted { AchievementDataBuilder.memoDate($0) < AchievementDataBuilder.memoDate($1) }
    }

    private var currentWeekStart: Date {
        Constants.mondayWeekStart(for: Date())
    }

    private var currentWeekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) ?? Date()
    }

    private func overdueMemosPreview(_ memos: [Memo]) -> String {
        let titles = memos.prefix(3).map { AchievementDataBuilder.shortText($0.content, limit: 18) }
        let suffix = memos.count > 3 ? " 외 \(memos.count - 3)개" : ""
        return (titles.joined(separator: ", ") + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moveOverdueMemosToToday(_ memos: [Memo]) {
        let today = Calendar.current.startOfDay(for: Date())
        rescheduleOverdueMemos(memos, targetDays: [today], messagePrefix: "오늘로 이동했습니다")
    }

    private func distributeOverdueMemosAcrossRemainingWeek(_ memos: [Memo]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = max(today, currentWeekStart)
        let daysUntilSunday = max(0, calendar.dateComponents([.day], from: start, to: currentWeekEnd).day ?? 0)
        let targetDays = (0..<max(1, daysUntilSunday)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
        rescheduleOverdueMemos(memos, targetDays: targetDays.isEmpty ? [today] : targetDays, messagePrefix: "남은 요일에 나눠 배치했습니다")
    }

    private func moveTimelineMemo(_ memoID: UUID, to targetDay: Date) {
        guard let memo = memos.first(where: { $0.id == memoID }) else { return }

        overdueRescheduleMessage = ""
        moveMemoSchedule(memo, to: Calendar.current.startOfDay(for: targetDay))
        memo.updatedAt = Date()
        scheduleLocalReminder(for: memo)

        do {
            try modelContext.save()
        } catch {
            overdueRescheduleMessage = "일정 이동에 실패했습니다: \(error.localizedDescription)"
            return
        }

        let dayText = weekdayText(targetDay)
        syncLinkedRemindersIfNeeded([memo], successMessage: "할일을 \(dayText)요일로 이동했습니다.")
    }

    private func rescheduleOverdueMemos(_ memos: [Memo], targetDays: [Date], messagePrefix: String) {
        guard !memos.isEmpty, !targetDays.isEmpty else { return }
        overdueRescheduleMessage = ""

        for (index, memo) in memos.enumerated() {
            let targetDay = targetDays[index % targetDays.count]
            moveMemoSchedule(memo, to: targetDay)
            memo.updatedAt = Date()
            scheduleLocalReminder(for: memo)
        }

        do {
            try modelContext.save()
        } catch {
            overdueRescheduleMessage = "일정 저장에 실패했습니다: \(error.localizedDescription)"
            return
        }

        syncLinkedRemindersIfNeeded(memos, successMessage: "\(memos.count)개를 \(messagePrefix).")
    }

    private func moveMemoSchedule(_ memo: Memo, to targetDay: Date) {
        switch (memo.startDate, memo.deadline) {
        case let (startDate?, deadline?):
            let newStartDate = date(on: targetDay, preservingTimeOf: startDate)
            memo.startDate = newStartDate
            memo.deadline = deadlineDate(on: targetDay, preservingTimeOf: deadline, notBefore: newStartDate)
        case let (startDate?, nil):
            memo.startDate = date(on: targetDay, preservingTimeOf: startDate)
        case let (nil, deadline?):
            memo.deadline = date(on: targetDay, preservingTimeOf: deadline)
        default:
            memo.startDate = date(on: targetDay, preservingTimeOf: Date())
        }
    }

    private func date(on targetDay: Date, preservingTimeOf sourceDate: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: sourceDate)
        return calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: targetDay
        ) ?? targetDay
    }

    private func deadlineDate(on targetDay: Date, preservingTimeOf sourceDate: Date, notBefore startDate: Date) -> Date {
        let deadline = date(on: targetDay, preservingTimeOf: sourceDate)
        guard deadline < startDate else { return deadline }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: targetDay) ?? startDate
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func scheduleLocalReminder(for memo: Memo) {
        let identifier = "memo.deadline.\(memo.id.uuidString)"
        guard !memo.isCompletedValue,
              !memo.isArchivedValue,
              let deadline = memo.deadline,
              let offset = memo.reminderOffsetMinutes else {
            NotificationManager.shared.cancel(identifier: identifier)
            return
        }

        let fireDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))
        NotificationManager.shared.scheduleMemoReminder(
            identifier: identifier,
            title: "메모 마감 알림",
            body: AchievementDataBuilder.shortText(memo.content, limit: 40),
            at: fireDate
        )
    }

    private func syncLinkedRemindersIfNeeded(_ memos: [Memo], successMessage: String) {
        let linkedMemos = memos.filter(\.isLinkedToRemindersValue)
        guard !linkedMemos.isEmpty else {
            overdueRescheduleMessage = successMessage
            clearOverdueRescheduleMessageLater()
            return
        }

        overdueRescheduleMessage = "\(successMessage) 미리알림을 동기화하는 중입니다."
        Task { @MainActor in
            var failedCount = 0
            for memo in linkedMemos {
                do {
                    memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(for: memo)
                    scheduleLocalReminder(for: memo)
                    try? modelContext.save()
                } catch {
                    failedCount += 1
                }
            }

            overdueRescheduleMessage = failedCount == 0
                ? "\(successMessage) 미리알림도 동기화했습니다."
                : "\(successMessage) 미리알림 \(failedCount)개는 동기화하지 못했습니다."
            clearOverdueRescheduleMessageLater()
        }
    }

    private func clearOverdueRescheduleMessageLater() {
        let message = overdueRescheduleMessage
        guard !message.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if overdueRescheduleMessage == message {
                overdueRescheduleMessage = ""
            }
        }
    }

    private var monthContent: some View {
        VStack(spacing: 14) {
            AchievementPeriodHeader(
                title: currentMonthTitle,
                subtitle: "월간 목표와 보상을 한 달 단위로 봅니다",
                leading: "이전달",
                trailing: "다음달",
                onLeading: {
                    moveDisplayedMonth(by: -1)
                },
                onTrailing: {
                    moveDisplayedMonth(by: 1)
                }
            )
            HStack(spacing: 10) {
                AchievementMetricCard(label: "등록 목표", value: "월간: \(monthlyGoals.count)", icon: "arrow.up.right.circle", valueSize: 14.5)
                AchievementMetricCard(label: "완료 목표", value: "월간: \(completedMonthlyGoalCount)", icon: "checkmark.seal", valueSize: 14.5)
                AchievementMetricCard(label: "가장 잘한 목표", value: bestMonthlyGoal?.title ?? "없음", icon: "trophy", valueSize: 14.5, isHighlighted: true) {
                    if let bestMonthlyGoal {
                        manageGoal(bestMonthlyGoal)
                    }
                }
                AchievementMetricCard(label: "흔들린 목표", value: shakyMonthlyGoal?.title ?? "없음", icon: "flag", valueSize: 14.5) {
                    if let shakyMonthlyGoal {
                        manageGoal(shakyMonthlyGoal)
                    }
                }
            }
            monthlyCalendar
            monthlyGoalList
            weeklyProgress
        }
    }

    private var monthlyGoalList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("월간 목표")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(monthlyGoals.count)개")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if monthlyGoals.isEmpty {
                Text("월간 목표를 추가하면 여기에 표시됩니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                VStack(spacing: 9) {
                    ForEach(monthlyGoals) { goal in
                        Button {
                            manageGoal(goal)
                        } label: {
                            HStack(spacing: 9) {
                                Text(goal.emoji)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(goal.done)/\(goal.total)")
                                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(PopoverChrome.inkSecondary)
                                            .monospacedDigit()
                                    }
                                    AchievementProgressBar(progress: goal.progress, color: goal.color)
                                }
                                Image(systemName: "pencil")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                            }
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .achievementDetailCard()
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("달성 기록")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("완료된 주간 목표와 월간 목표를 한 곳에서 봅니다.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                AchievementMetricCard(label: "달성 목표", value: "\(completedAchievementGoals.count)", icon: "checkmark.seal")
                AchievementMetricCard(label: "주간", value: "\(completedWeeklyGoalCount)", icon: "calendar.badge.clock")
                AchievementMetricCard(label: "월간", value: "\(completedMonthlyGoalCount)", icon: "calendar")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("완료된 목표")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    AchievementSegmentedPicker(selection: $selectedRecordScope, values: AchievementRecordScope.allCases)
                }

                if visibleCompletedAchievementGoals.isEmpty {
                    Text("아직 완료된 주간 또는 월간 목표가 없습니다.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(completedAchievementGoalGroups) { group in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(group.title)
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkSecondary)
                                ForEach(group.goals) { goal in
                                    achievementRecordRow(goal)
                                }
                            }
                        }
                    }
                }
            }
            .achievementDetailCard()
        }
    }

    private func achievementRecordRow(_ goal: AchievementGoal) -> some View {
        Button {
            manageGoal(goal)
        } label: {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(1)
                    Text("\(goal.cadence) · \(goal.rule) · \(achievementRecordDateText(goal.recordDate)) 달성")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                AchievementRewardBadge(reward: goal.reward, color: goal.color)
            }
            .padding(10)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var journeyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            journeyHeader
            roleChips

            if let role = selectedRole {
                let imageURL = AchievementJourneyImageStore.imageURL(for: role.id)
                let selectedVision = selectedJourneyVision(for: role)
                let displayRole = AchievementRole(
                    id: role.id,
                    emoji: role.emoji,
                    name: role.name,
                    vision: journeyVisionText(for: role, selectedVision: selectedVision)
                )
                HStack(alignment: .top, spacing: 14) {
                    journeyPersonaCard(
                        role: displayRole,
                        imageURL: imageURL,
                        showsImageOptions: $showsJourneyImageOptions,
                        onAddImage: {
                        chooseJourneyImage(for: role)
                        },
                        onResetImage: {
                            resetJourneyImage(for: role)
                        }
                    )
                        .frame(width: 270)

                    VStack(alignment: .leading, spacing: 12) {
                        AchievementJourneyScene(
                            role: displayRole,
                            destinationImageURL: imageURL,
                            currentGoal: journeyCurrentGoal,
                            milestones: journeyFlagSlots,
                            progress: journeyProgress
                        )
                        .frame(height: 390)

                        journeyFlagSelectorBar

                        HStack(alignment: .top, spacing: 12) {
                            journeyStatsCard
                            journeyBacklinkCard
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    AchievementEmptyDetailCard(message: "페르소나와 비전을 추가하면 여정이 표시됩니다.")
                    Button {
                        showPersonaVisionComposer = true
                    } label: {
                        Label("페르소나와 비전 추가", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accentInk)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var journeyHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("여정")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("페르소나와 여러 비전을 연결해 목표의 목적지를 관리합니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                journeyVisionSelector
                    .padding(.top, 4)
            }
            Spacer()
            Button {
                showPersonaVisionComposer = true
            } label: {
                Label("페르소나/비전", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var journeyVisionSelector: some View {
        if let role = selectedRole {
            let visions = visionGoals(for: role)
            if !visions.isEmpty {
                Button {
                    showsJourneyVisionOptions.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Text("비전")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(PopoverChrome.accentSoft.opacity(0.72), in: Capsule())
                        Text(selectedJourneyVision(for: role)?.title ?? "비전 선택")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                            .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsJourneyVisionOptions, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("비전 선택")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)

                        ForEach(visions) { vision in
                            Button {
                                selectedJourneyVisionID = vision.id
                                showsJourneyVisionOptions = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedJourneyVisionID == vision.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(selectedJourneyVisionID == vision.id ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                    Text(vision.title)
                                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(
                                    selectedJourneyVisionID == vision.id ? PopoverChrome.accentSoft.opacity(0.68) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(width: 280)
                    .background(PopoverChrome.card)
                }
            }
        }
    }

    @ViewBuilder
    private var journeyFlagSelectorBar: some View {
        if selectedRole != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("여정 깃발")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Text("월간 목표를 직접 지정합니다")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: min(5, clampedJourneyMaxFlagCount)), spacing: 7) {
                    ForEach(Array(journeyFlagSlots.enumerated()), id: \.offset) { index, goal in
                        Button {
                            selectedJourneyFlagIndex = index
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: goal == nil ? "flag" : "flag.fill")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(goal == nil ? PopoverChrome.inkTertiary : PopoverChrome.accent)
                                Text(goal.map { AchievementDataBuilder.shortText($0.title, limit: 12) } ?? "\(index + 1)번")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(goal == nil ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 32)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                    .stroke(goal == nil ? PopoverChrome.border : PopoverChrome.accent.opacity(0.34), lineWidth: PopoverChrome.borderWidth)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { selectedJourneyFlagIndex == index },
                            set: { isPresented in
                                if !isPresented {
                                    selectedJourneyFlagIndex = nil
                                }
                            }
                        ), arrowEdge: .bottom) {
                            journeyFlagPicker(index: index)
                        }
                    }
                }
            }
            .padding(12)
            .background(PopoverChrome.surfaceAlt.opacity(0.68), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
        }
    }

    private func journeyFlagPicker(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1)번 깃발")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)

            Button {
                setJourneyFlagGoal(nil, at: index)
            } label: {
                journeyFlagPickerRow(title: "비워두기", systemImage: "flag", isSelected: journeyFlagSlots[index] == nil)
            }
            .buttonStyle(.plain)

            if selectedJourneyMonthlyGoals.isEmpty {
                Text("선택할 수 있는 월간 목표가 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            } else {
                ForEach(selectedJourneyMonthlyGoals) { goal in
                    Button {
                        setJourneyFlagGoal(goal, at: index)
                    } label: {
                        journeyFlagPickerRow(
                            title: "\(goal.emoji) \(goal.title)",
                            systemImage: "target",
                            isSelected: journeyFlagSlots[index]?.id == goal.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(PopoverChrome.card)
    }

    private func journeyFlagPickerRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? PopoverChrome.accent : PopoverChrome.inkTertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? PopoverChrome.accentSoft.opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
    }

    private func journeyPersonaCard(
        role: AchievementRole,
        imageURL: URL?,
        showsImageOptions: Binding<Bool>,
        onAddImage: @escaping () -> Void,
        onResetImage: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.12, blue: 0.13),
                                Color(red: 0.18, green: 0.24, blue: 0.18),
                                PopoverChrome.accent.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 210)
                    .overlay(alignment: .center) {
                        if let imageURL, let image = NSImage(contentsOf: imageURL) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 270, height: 210)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.56)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            VStack(spacing: 10) {
                                Text(role.emoji)
                                    .font(.system(size: 54))
                                Text(role.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                Text(imageURL == nil ? "페르소나 이미지" : role.name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: Capsule())
                    .padding(.bottom, 14)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("비전")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                Text(role.vision.isEmpty ? "비전을 추가하면 여정의 목적지로 표시됩니다." : role.vision)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    // TODO: AI 이미지 생성 연동 시 실제 생성 플로우로 연결합니다.
                } label: {
                    Text("AI 이미지 생성")
                        .frame(maxWidth: .infinity)
                }
                .disabled(true)
                .achievementJourneyActionStyle(isPrimary: true)

                if imageURL == nil {
                    Button {
                        onAddImage()
                    } label: {
                        Text("이미지 추가")
                            .frame(maxWidth: .infinity)
                    }
                    .achievementJourneyActionStyle(isPrimary: false)
                } else {
                    Button {
                        showsImageOptions.wrappedValue.toggle()
                    } label: {
                        Text("이미지 변경")
                            .frame(maxWidth: .infinity)
                    }
                    .achievementJourneyActionStyle(isPrimary: false)
                    .popover(isPresented: showsImageOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                showsImageOptions.wrappedValue = false
                                onAddImage()
                            } label: {
                                Label("이미지 변경", systemImage: "photo")
                            }
                            .buttonStyle(.plain)

                            Button {
                                showsImageOptions.wrappedValue = false
                                onResetImage()
                            } label: {
                                Label("기본 이미지로 되돌리기", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(12)
                        .background(PopoverChrome.card)
                    }
                }
            }

            Text("AI 생성은 임시 비활성화 상태입니다.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
        .achievementDetailCard()
    }

    private var journeyStatsCard: some View {
        return VStack(alignment: .leading, spacing: 11) {
            Text("비전 연결 현황")
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)

            HStack(spacing: 10) {
                AchievementJourneyStat(label: "월간 목표", value: "\(selectedJourneyMonthlyGoals.count)")
                AchievementJourneyStat(label: "연결된 일", value: "\(journeyLinkedMemos.count)")
                AchievementJourneyStat(label: "완료한 일", value: "\(journeyLinkedMemos.filter(\.isCompletedValue).count)")
            }

            if let goal = journeyCurrentGoal {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .lineLimit(2)
                    AchievementProgressBar(progress: goal.progress, color: goal.color)
                    Text(journeyProgressCaption(for: goal))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .lineLimit(1)
                }
                .padding(12)
                .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .achievementDetailCard()
    }

    private var journeyBacklinkCard: some View {
        let recentMemos = Array(journeyLinkedMemos.prefix(4))

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("최근 연결된 일")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(recentMemos.count)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if recentMemos.isEmpty {
                Text("선택한 비전의 월간 목표와 연결된 일이 없습니다.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                ForEach(recentMemos, id: \.id) { memo in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(memo.isCompletedValue ? PopoverChrome.accent : Color.blue)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AchievementDataBuilder.shortText(memo.content, limit: 28))
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(PopoverChrome.ink)
                                .lineLimit(1)
                            Text(AchievementDataBuilder.todoMetaText(for: memo))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .achievementDetailCard()
    }

    private var roleChips: some View {
        HStack(spacing: 8) {
            ForEach(roles) { role in
                Button {
                    selectedRoleID = role.id
                    selectedJourneyVisionID = selectedJourneyVision(for: role)?.id
                    selectedGoalID = goals.first(where: { $0.roleName == role.id })?.id ?? selectedGoalID
                } label: {
                    HStack(spacing: 7) {
                        Text(role.emoji)
                        Text(role.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("\(visionGoals(for: role).count)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PopoverChrome.surfaceAlt.opacity(0.9), in: Capsule())
                    }
                    .foregroundStyle(selectedRoleID == role.id ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(selectedRoleID == role.id ? PopoverChrome.accent : PopoverChrome.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func journeyProgressCaption(for goal: AchievementGoal) -> String {
        let progressTarget = goal.cadence == "월간" ? "연결된 주간 목표 진행" : "연결된 일 진행"
        return "\(goal.done)/\(goal.total) · \(progressTarget)"
    }

    private var selectedRole: AchievementRole? {
        roles.first { $0.id == selectedRoleID } ?? roles.first
    }

    private func visionGoals(for role: AchievementRole) -> [AchievementGoal] {
        goals
            .filter { $0.cadence == "비전" && $0.roleName == role.id }
            .sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }
    }

    private func selectedJourneyVision(for role: AchievementRole) -> AchievementGoal? {
        let visions = visionGoals(for: role)
        if let selectedJourneyVisionID,
           let selected = visions.first(where: { $0.id == selectedJourneyVisionID }) {
            return selected
        }
        return visions.first
    }

    private var selectedRoleGoals: [AchievementGoal] {
        guard let role = selectedRole else { return [] }
        return goals.filter { $0.roleName == role.id && $0.cadence != "역할" }
    }

    private var selectedJourneyMonthlyGoals: [AchievementGoal] {
        guard let role = selectedRole else { return [] }
        let selectedVision = selectedJourneyVision(for: role)
        let visionKeys = [
            selectedVision?.title,
            selectedVision?.vision,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return goals.filter { goal in
            guard goal.roleName == role.id, goal.cadence == "월간" else { return false }
            guard !visionKeys.isEmpty else { return true }
            let goalVision = goal.vision.trimmingCharacters(in: .whitespacesAndNewlines)
            return visionKeys.contains(goalVision)
        }
    }

    private var clampedJourneyMaxFlagCount: Int {
        min(max(journeyMaxFlagCount, Constants.achievementJourneyMaxFlagCountRange.lowerBound), Constants.achievementJourneyMaxFlagCountRange.upperBound)
    }

    private var journeyFlagStorageKey: String? {
        guard let role = selectedRole else { return nil }
        let visionID = selectedJourneyVision(for: role)?.id.uuidString ?? "none"
        return "\(role.id)|\(visionID)"
    }

    private var journeyFlagSlots: [AchievementGoal?] {
        _ = journeyFlagRefreshID
        guard let key = journeyFlagStorageKey else {
            return Array(repeating: nil, count: clampedJourneyMaxFlagCount)
        }
        let storedIDs = AchievementJourneyFlagStore.goalIDs(for: key, maxCount: clampedJourneyMaxFlagCount)
        let goalsByID = Dictionary(uniqueKeysWithValues: selectedJourneyMonthlyGoals.map { ($0.id, $0) })
        var slots = storedIDs.map { id in
            id.flatMap { goalsByID[$0] }
        }
        while slots.count < clampedJourneyMaxFlagCount {
            slots.append(nil)
        }
        return Array(slots.prefix(clampedJourneyMaxFlagCount))
    }

    private var journeyFlagGoals: [AchievementGoal] {
        journeyFlagSlots.compactMap { $0 }
    }

    private func setJourneyFlagGoal(_ goal: AchievementGoal?, at index: Int) {
        guard let key = journeyFlagStorageKey else { return }
        AchievementJourneyFlagStore.setGoalID(goal?.id, at: index, for: key, maxCount: clampedJourneyMaxFlagCount)
        selectedJourneyFlagIndex = nil
        journeyFlagRefreshID = UUID()
    }

    private func journeyVisionText(for role: AchievementRole, selectedVision: AchievementGoal?) -> String {
        if let selectedVision {
            let selectedVisionText = selectedVision.vision.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedVisionText.isEmpty ? selectedVision.title : selectedVisionText
        }

        let roleVision = role.vision.trimmingCharacters(in: .whitespacesAndNewlines)
        if !roleVision.isEmpty {
            return roleVision
        }

        let roleGoals = goals.filter { $0.roleName == role.id }
        let matchingVisionGoal = roleGoals.first { $0.cadence == "비전" }
        let linkedVisionText = [
            matchingVisionGoal?.vision,
            matchingVisionGoal?.title,
            roleGoals.first { !$0.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.vision,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        if let linkedVisionText {
            return linkedVisionText
        }

        let allVisionGoals = goals.filter { $0.cadence == "비전" }
        if allVisionGoals.count == 1 {
            let onlyVision = allVisionGoals[0]
            return onlyVision.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? onlyVision.title
                : onlyVision.vision
        }

        return ""
    }

    private var journeyCurrentGoal: AchievementGoal? {
        if let selectedGoal,
           journeyFlagGoals.contains(where: { $0.id == selectedGoal.id }) {
            return selectedGoal
        }
        return journeyFlagGoals.max { lhs, rhs in
            if lhs.progress == rhs.progress {
                return lhs.done < rhs.done
            }
            return lhs.progress < rhs.progress
        }
    }

    private var journeyProgress: Double {
        let measurableGoals = journeyFlagGoals.filter { $0.total > 0 }
        guard !measurableGoals.isEmpty else { return 0 }
        let total = measurableGoals.reduce(0) { $0 + $1.total }
        let done = measurableGoals.reduce(0) { $0 + min($1.done, $1.total) }
        return min(1, Double(done) / Double(total))
    }

    private var selectedRoleLinkedMemos: [Memo] {
        let ids = Set(selectedRoleGoals.flatMap(\.sourceMemoIDs))
        return memos
            .filter { ids.contains($0.id) }
            .sorted { AchievementDataBuilder.memoDate($0) > AchievementDataBuilder.memoDate($1) }
    }

    private var journeyLinkedMemos: [Memo] {
        guard let role = selectedRole else { return [] }
        let monthlyGoals = selectedJourneyMonthlyGoals
        let monthlyTitles = Set(monthlyGoals.map(\.title))
        let linkedGoalIDs = monthlyGoals.flatMap(\.sourceMemoIDs)
        let linkedWeeklyGoalIDs = goals
            .filter { goal in
                goal.roleName == role.id
                    && goal.cadence == "주간"
                    && goal.monthGoal.map { monthlyTitles.contains($0) } == true
            }
            .flatMap(\.sourceMemoIDs)
        let ids = Set(linkedGoalIDs + linkedWeeklyGoalIDs)

        return memos
            .filter { ids.contains($0.id) }
            .sorted { AchievementDataBuilder.memoDate($0) > AchievementDataBuilder.memoDate($1) }
    }

    private func savePersonaVisionDraft(_ draft: AchievementPersonaVisionDraft) throws {
        let personaName = AchievementDataBuilder.shortText(draft.personaName, limit: 40)
        let visionTitle = AchievementDataBuilder.shortText(draft.visionTitle, limit: 40)
        let visionText = draft.visionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !goalRecords.contains(where: { $0.cadence == "역할" && $0.title == personaName }) {
            let personaRecord = AchievementGoalRecord(
                title: personaName,
                emoji: draft.personaEmoji,
                cadence: "역할",
                rule: "페르소나 방향 유지",
                targetCount: 1,
                targetValueText: "1개",
                periodText: "계속",
                rewardText: "",
                colorHex: "#E87333",
                roleName: personaName,
                vision: "",
                linkedMemoIDs: []
            )
            modelContext.insert(personaRecord)
        }

        let visionRecord = AchievementGoalRecord(
            title: visionTitle,
            emoji: draft.visionEmoji,
            cadence: "비전",
            rule: "비전 방향 유지",
            targetCount: 1,
            targetValueText: "1개",
            periodText: "장기",
            rewardText: "",
            colorHex: "#7A52D4",
            roleName: personaName,
            vision: visionText.isEmpty ? visionTitle : visionText,
            linkedMemoIDs: []
        )
        modelContext.insert(visionRecord)
        try modelContext.save()

        selectedRoleID = personaName
        selectedJourneyVisionID = visionRecord.id
        selectedGoalID = visionRecord.id
        showPersonaVisionComposer = false
    }

    private func chooseJourneyImage(for role: AchievementRole) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "\(role.name) 이미지 선택"
        panel.prompt = "추가"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            _ = try AchievementJourneyImageStore.saveImage(from: url, for: role.id)
            journeyImageRefreshID = UUID()
        } catch {
            overdueRescheduleMessage = "이미지를 추가하지 못했습니다: \(error.localizedDescription)"
            clearOverdueRescheduleMessageLater()
        }
    }

    private func resetJourneyImage(for role: AchievementRole) {
        AchievementJourneyImageStore.removeImage(for: role.id)
        journeyImageRefreshID = UUID()
    }

    private var monthlyCalendar: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<31
        let firstDay = dateForCurrentMonth(day: 1, calendar: calendar)
        let leadingBlankCount = (calendar.component(.weekday, from: firstDay) + 5) % 7
        let month = calendar.component(.month, from: displayedMonth)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(month)월 성취 캘린더")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 8)
                if !monthCalendarLegendGoals.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(monthCalendarLegendGoals) { goal in
                                AchievementCalendarLegendButton(goal: goal) {
                                    manageGoal(goal)
                                }
                            }
                        }
                        .frame(width: 360, alignment: .trailing)
                    }
                    .frame(width: 360, alignment: .trailing)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 2)
                }
                ForEach(0..<leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                ForEach(Array(range), id: \.self) { day in
                    let dayDate = dateForCurrentMonth(day: day, calendar: calendar)
                    let dayGoals = monthCalendarGoals(on: dayDate, calendar: calendar)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(day)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(calendar.isDateInToday(dayDate) ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                        HStack(spacing: 3) {
                            ForEach(dayGoals.prefix(3)) { goal in
                                Circle().fill(goal.color).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .padding(6)
                    .background(PopoverChrome.surfaceAlt.opacity(calendar.isDateInToday(dayDate) ? 1 : 0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
            }
        }
        .achievementDetailCard()
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("주차별 월간 목표 진행률")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(currentMonthWeekProgress) { weekProgress in
                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                                    .fill(PopoverChrome.accent)
                                    .frame(height: proxy.size.height * weekProgress.progress)
                            }
                        }
                        .frame(width: 30, height: 106)
                        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous))
                        Text("\(weekProgress.week)주")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        Text(weekProgress.percentText)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .monospacedDigit()
                        Text(weekProgress.isCurrent ? "진행 중" : "\(weekProgress.completed)/\(weekProgress.total)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(weekProgress.isCurrent ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .achievementDetailCard()
    }

    private var monthlyGoals: [AchievementGoal] {
        goals.filter { $0.cadence == "월간" }
    }

    private var weeklyGoals: [AchievementGoal] {
        goals.filter { $0.cadence == "주간" }
    }

    private var completedAchievementGoals: [AchievementGoal] {
        goals.filter { goal in
            (goal.cadence == "주간" || goal.cadence == "월간") && goal.total > 0 && goal.isComplete
        }
    }

    private var visibleCompletedAchievementGoals: [AchievementGoal] {
        completedAchievementGoals
            .filter { goal in
                switch selectedRecordScope {
                case .all:
                    return true
                case .weekly:
                    return goal.cadence == "주간"
                case .monthly:
                    return goal.cadence == "월간"
                }
            }
            .sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }
    }

    private var completedAchievementGoalGroups: [AchievementRecordMonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleCompletedAchievementGoals) { goal in
            calendar.dateInterval(of: .month, for: goal.recordDate)?.start ?? calendar.startOfDay(for: goal.recordDate)
        }

        return grouped.keys.sorted(by: >).map { monthStart in
            let goals = (grouped[monthStart] ?? []).sorted { lhs, rhs in
                if lhs.recordDate == rhs.recordDate {
                    return lhs.title < rhs.title
                }
                return lhs.recordDate > rhs.recordDate
            }
            return AchievementRecordMonthGroup(
                id: "\(calendar.component(.year, from: monthStart))-\(calendar.component(.month, from: monthStart))",
                title: achievementRecordMonthTitle(monthStart),
                goals: goals
            )
        }
    }

    private func achievementRecordMonthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    private func achievementRecordDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private var monthCalendarLegendGoals: [AchievementGoal] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth)
        return monthlyGoals.filter { goal in
            memos.contains { memo in
                goal.sourceMemoIDs.contains(memo.id)
                    && monthInterval?.contains(AchievementDataBuilder.memoDate(memo)) == true
            }
        }
    }

    private var completedMonthlyGoalCount: Int {
        monthlyGoals.filter(\.isComplete).count
    }

    private var completedWeeklyGoalCount: Int {
        weeklyGoals.filter(\.isComplete).count
    }

    private var weeklyPendingRewardCount: Int {
        weeklyGoals.filter { $0.reward.status == .pending }.count
    }

    private var weeklyLinkedMemoCount: Int {
        Set(weeklyGoals.flatMap(\.sourceMemoIDs)).count
    }

    private var bestMonthlyGoal: AchievementGoal? {
        monthlyGoals.max { lhs, rhs in
            if lhs.progress == rhs.progress {
                return lhs.done < rhs.done
            }
            return lhs.progress < rhs.progress
        }
    }

    private var shakyMonthlyGoal: AchievementGoal? {
        monthlyGoals.min { lhs, rhs in
            if lhs.progress == rhs.progress {
                return lhs.done < rhs.done
            }
            return lhs.progress < rhs.progress
        }
    }

    private var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    private var currentMonthWeekProgress: [AchievementMonthlyWeekProgress] {
        let calendar = Calendar.current
        let today = Date()
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstDay = monthInterval.start
        let leadingBlankCount = (calendar.component(.weekday, from: firstDay) + 5) % 7
        let weekCount = Int(ceil(Double(leadingBlankCount + dayRange.count) / 7.0))
        let currentWeek = calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
            ? weekIndexInCurrentMonth(for: today, calendar: calendar)
            : nil

        return (1...max(1, weekCount)).map { week in
            let weekStart = calendar.date(byAdding: .day, value: ((week - 1) * 7) - leadingBlankCount, to: firstDay) ?? firstDay
            let rawWeekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let effectiveStart = max(weekStart, monthInterval.start)
            let effectiveEnd = min(rawWeekEnd, monthInterval.end)

            let goalStates = monthlyGoals.compactMap { goal -> Bool? in
                let weekMemos = memos
                    .filter { goal.sourceMemoIDs.contains($0.id) }
                    .filter { memo in
                        let date = AchievementDataBuilder.memoDate(memo)
                        return date >= effectiveStart && date < effectiveEnd
                    }
                guard !weekMemos.isEmpty else { return nil }
                return weekMemos.allSatisfy(\.isCompletedValue)
            }

            return AchievementMonthlyWeekProgress(
                week: week,
                completed: goalStates.filter { $0 }.count,
                total: goalStates.count,
                isCurrent: week == currentWeek
            )
        }
    }

    private func weekIndexInCurrentMonth(for date: Date, calendar: Calendar) -> Int {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return 1 }
        let firstDay = monthInterval.start
        let leadingBlankCount = (calendar.component(.weekday, from: firstDay) + 5) % 7
        let day = calendar.component(.day, from: date)
        return ((leadingBlankCount + day - 1) / 7) + 1
    }

    private func ensureSelection() {
        if selectedGoalID == nil || !goals.contains(where: { $0.id == selectedGoalID }) {
            selectedGoalID = goals.first?.id
        }
        if selectedRoleID.isEmpty || !roles.contains(where: { $0.id == selectedRoleID }) {
            selectedRoleID = roles.first?.id ?? ""
        }
        if let role = selectedRole {
            let visions = visionGoals(for: role)
            if selectedJourneyVisionID == nil || !visions.contains(where: { $0.id == selectedJourneyVisionID }) {
                selectedJourneyVisionID = visions.first?.id
            }
        } else {
            selectedJourneyVisionID = nil
        }
    }

    private func deleteGoal(_ goal: AchievementGoal) {
        guard let record = goalRecords.first(where: { $0.id == goal.id }) else { return }
        deleteGoalRecord(record)
    }

    private func manageGoal(_ goal: AchievementGoal) {
        managingGoalID = goal.id
    }

    private func linkableMemos(for record: AchievementGoalRecord) -> [Memo] {
        let linkedIDs = Set(record.linkedMemoIDs)
        return memos.filter { !$0.isArchivedValue || linkedIDs.contains($0.id) }
    }

    private func childCadence(for cadence: String) -> String? {
        switch cadence {
        case "연간":
            return "월간"
        case "월간":
            return "주간"
        default:
            return nil
        }
    }

    private func childRecords(for record: AchievementGoalRecord) -> [AchievementGoalRecord] {
        guard let childCadence = childCadence(for: record.cadence) else { return [] }
        return goalRecords
            .filter { child in
                guard child.cadence == childCadence else { return false }
                switch record.cadence {
                case "연간":
                    return nonEmpty(child.yearGoal) == record.title
                case "월간":
                    return nonEmpty(child.monthGoal) == record.title
                default:
                    return false
                }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func updateGoalRecord(_ record: AchievementGoalRecord, draft: AchievementGoalEditDraft) {
        let oldTitle = record.title
        let newTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        record.title = newTitle.isEmpty ? record.title : newTitle
        record.emoji = draft.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.emoji : draft.emoji
        record.rule = draft.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        record.targetCount = max(1, draft.targetCount)
        record.rewardText = draft.rewardText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let linkedMemoIDs = draft.linkedMemoIDs {
            record.linkedMemoIDs = linkedMemoIDs
            record.targetCount = max(1, linkedMemoIDs.count)
        }
        record.updatedAt = Date()

        syncGoalTitleReferences(oldTitle: oldTitle, newTitle: record.title, cadence: record.cadence)
        connectDescendantGoals(of: record)
        try? modelContext.save()
        managingGoalID = nil
    }

    private func addChildGoal(to parent: AchievementGoalRecord, title: String, emoji: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let childCadence = childCadence(for: parent.cadence), !trimmedTitle.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AchievementGoalRecord(
            title: trimmedTitle,
            emoji: trimmedEmoji.isEmpty ? defaultEmoji(for: childCadence) : String(trimmedEmoji.prefix(1)),
            cadence: childCadence,
            rule: "",
            targetCount: 1,
            targetValueText: nil,
            periodText: defaultPeriodText(for: childCadence),
            rewardText: "",
            colorHex: parent.colorHex,
            roleName: parent.roleName,
            vision: parent.vision,
            yearGoal: childCadence == "월간" ? parent.title : parent.yearGoal,
            quarterGoal: nil,
            monthGoal: childCadence == "주간" ? parent.title : parent.monthGoal,
            linkedMemoIDs: []
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func updateChildGoal(_ record: AchievementGoalRecord, title: String, emoji: String) {
        let oldTitle = record.title
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            record.title = newTitle
        }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmoji.isEmpty {
            record.emoji = String(trimmedEmoji.prefix(1))
        }
        record.updatedAt = Date()
        syncGoalTitleReferences(oldTitle: oldTitle, newTitle: record.title, cadence: record.cadence)
        connectDescendantGoals(of: record)
        try? modelContext.save()
    }

    private func defaultEmoji(for cadence: String) -> String {
        switch cadence {
        case "연간": return "🏁"
        case "월간": return "📅"
        case "주간": return "🎯"
        default: return "🎯"
        }
    }

    private func defaultPeriodText(for cadence: String) -> String? {
        switch cadence {
        case "연간": return "올해"
        case "월간": return "이번 달"
        case "주간": return "이번 주"
        default: return nil
        }
    }

    private func deleteGoalRecord(_ record: AchievementGoalRecord) {
        let deletedID = record.id
        modelContext.delete(record)
        try? modelContext.save()
        if selectedGoalID == deletedID {
            selectedGoalID = goals.first(where: { $0.id != deletedID })?.id
        }
        if managingGoalID == deletedID {
            managingGoalID = nil
        }
    }

    private func syncGoalTitleReferences(oldTitle: String, newTitle: String, cadence: String) {
        guard oldTitle != newTitle else { return }
        guard !oldTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for record in goalRecords {
            switch cadence {
            case "역할":
                if record.roleName == oldTitle {
                    record.roleName = newTitle
                    record.updatedAt = Date()
                }
            case "비전":
                if record.vision == oldTitle {
                    record.vision = newTitle
                    record.updatedAt = Date()
                }
            case "연간":
                if record.yearGoal == oldTitle {
                    record.yearGoal = newTitle
                    record.updatedAt = Date()
                }
            case "월간":
                if record.monthGoal == oldTitle {
                    record.monthGoal = newTitle
                    record.updatedAt = Date()
                }
            default:
                break
            }
        }
    }

    private func connectChildGoals(_ childGoalIDs: Set<UUID>, to parent: AchievementGoalRecord) {
        guard !childGoalIDs.isEmpty else { return }

        for child in goalRecords where childGoalIDs.contains(child.id) {
            child.roleName = parent.roleName
            child.vision = parent.vision

            switch parent.cadence {
            case "연간":
                child.yearGoal = parent.title
            case "월간":
                child.yearGoal = parent.yearGoal
                child.quarterGoal = nil
                child.monthGoal = parent.title
            default:
                break
            }

            child.updatedAt = Date()
            connectDescendantGoals(of: child)
        }
    }

    private func connectDescendantGoals(of parent: AchievementGoalRecord) {
        switch parent.cadence {
        case "연간":
            for month in goalRecords where month.cadence == "월간" && nonEmpty(month.yearGoal) == parent.title {
                month.roleName = parent.roleName
                month.vision = parent.vision
                month.yearGoal = parent.title
                month.quarterGoal = nil
                month.updatedAt = Date()
                connectDescendantGoals(of: month)
            }
        case "월간":
            for week in goalRecords where week.cadence == "주간" && nonEmpty(week.monthGoal) == parent.title {
                week.roleName = parent.roleName
                week.vision = parent.vision
                week.yearGoal = parent.yearGoal
                week.quarterGoal = nil
                week.monthGoal = parent.title
                week.updatedAt = Date()
            }
        default:
            break
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cadenceRank(_ cadence: String) -> Int {
        switch cadence {
        case "연간": return 0
        case "월간": return 1
        case "주간": return 2
        default: return 3
        }
    }

    private func dateForCurrentMonth(day: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        components.day = day
        return calendar.date(from: components) ?? displayedMonth
    }

    private func moveDisplayedMonth(by monthOffset: Int) {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        if let nextMonth = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) {
            displayedMonth = nextMonth
        }
    }

    private func monthCalendarGoals(on date: Date, calendar: Calendar) -> [AchievementGoal] {
        monthlyGoals.filter { goal in
            memos.contains { memo in
                goal.sourceMemoIDs.contains(memo.id)
                    && calendar.isDate(AchievementDataBuilder.memoDate(memo), inSameDayAs: date)
            }
        }
    }

}

private struct AchievementJourneyScene: View {
    let role: AchievementRole
    let destinationImageURL: URL?
    let currentGoal: AchievementGoal?
    let milestones: [AchievementGoal?]
    let progress: Double

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let cappedPhase = walkerPhase(at: context.date)
                let walkerPoint = routePoint(at: cappedPhase, in: size)
                let beamPoint = routePoint(at: min(1, cappedPhase + 0.08), in: size)
                let destinationPoint = CGPoint(x: size.width - 72, y: size.height * 0.31)
                let frameIndex = Int(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.75) / 0.25)

                ZStack {
                    journeyBackground(in: size)

                    forestLayer(in: size)
                    groundLayer(in: size)
                    pathGroundLayer(in: size)
                    fireflyLayer(in: size, date: context.date)

                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 42, nearWidth: 4, capDepth: 24)
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.22).opacity(0.28))
                        .blur(radius: 18)
                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 30, nearWidth: 2.8, capDepth: 18)
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.31))
                        .blur(radius: 7)
                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 15, nearWidth: 1.7, capDepth: 10)
                        .fill(Color(red: 1.0, green: 0.90, blue: 0.48).opacity(0.18))
                        .blur(radius: 2)
                    lanternGlow(from: walkerPoint, to: beamPoint)

                    routePath(in: size)
                        .stroke(Color(red: 0.10, green: 0.07, blue: 0.04).opacity(0.54), style: StrokeStyle(lineWidth: 31, lineCap: .round, lineJoin: .round))
                        .blur(radius: 0.4)
                    routePath(in: size)
                        .stroke(Color(red: 0.68, green: 0.42, blue: 0.17).opacity(0.88), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
                    routePath(in: size)
                        .stroke(Color(red: 0.96, green: 0.66, blue: 0.32).opacity(0.48), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    completedRoutePath(in: size)
                        .stroke(Color(red: 1.0, green: 0.73, blue: 0.38).opacity(0.66), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color(red: 1.0, green: 0.58, blue: 0.24).opacity(0.42), radius: 7, x: 0, y: 0)

                    unexploredFogLayer(in: size)

                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, goal in
                        let point = routePoint(at: milestonePhase(index, total: milestones.count), in: size)
                        AchievementJourneyMilestone(goal: goal, index: index, isLit: Double(index + 1) / Double(max(1, milestones.count)) <= max(progress, 0.08))
                            .position(x: point.x, y: point.y - 54)
                    }

                    AchievementJourneyDestination(role: role, imageURL: destinationImageURL)
                        .position(destinationPoint)

                    AchievementJourneyWalker(frameIndex: frameIndex)
                        .position(walkerPoint)

                    Text("“\(visionQuote)”")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(Color(red: 0.80, green: 0.76, blue: 0.67).opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.32), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: min(460, size.width - 56))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 19)
                }
                .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var visionQuote: String {
        let trimmed = role.vision.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "오늘의 일이 목적지로 이어진다" : trimmed
    }

    private func walkerPhase(at date: Date) -> CGFloat {
        let startPhase: CGFloat = 0.04
        let endPhase = max(startPhase, min(0.96, CGFloat(max(0, min(1, progress))) * 0.96))
        return endPhase
    }

    private var starPositions: [CGPoint] {
        [
            CGPoint(x: 0.10, y: 0.17),
            CGPoint(x: 0.18, y: 0.28),
            CGPoint(x: 0.30, y: 0.14),
            CGPoint(x: 0.42, y: 0.24),
            CGPoint(x: 0.57, y: 0.12),
            CGPoint(x: 0.66, y: 0.30),
            CGPoint(x: 0.74, y: 0.18),
            CGPoint(x: 0.84, y: 0.33),
            CGPoint(x: 0.92, y: 0.15),
            CGPoint(x: 0.25, y: 0.40),
            CGPoint(x: 0.52, y: 0.38),
            CGPoint(x: 0.70, y: 0.46),
        ]
    }

    private var fireflyPositions: [CGPoint] {
        [
            CGPoint(x: 0.14, y: 0.23),
            CGPoint(x: 0.32, y: 0.36),
            CGPoint(x: 0.45, y: 0.64),
            CGPoint(x: 0.59, y: 0.25),
            CGPoint(x: 0.69, y: 0.40),
            CGPoint(x: 0.88, y: 0.52),
            CGPoint(x: 0.18, y: 0.58),
            CGPoint(x: 0.76, y: 0.70),
        ]
    }

    private func journeyBackground(in size: CGSize) -> some View {
        return ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.07)

            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.15, blue: 0.23),
                    Color(red: 0.07, green: 0.14, blue: 0.17),
                    Color(red: 0.05, green: 0.10, blue: 0.09),
                    Color(red: 0.05, green: 0.08, blue: 0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.23, blue: 0.32).opacity(0.95),
                    .clear,
                ],
                center: UnitPoint(x: 0.78, y: -0.10),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.65
            )

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.87, green: 0.92, blue: 1.0).opacity(index % 3 == 0 ? 0.72 : 0.38))
                    .frame(width: index % 4 == 0 ? 2.5 : 1.7, height: index % 4 == 0 ? 2.5 : 1.7)
                    .position(
                        x: size.width * starPositions[index].x,
                        y: size.height * starPositions[index].y
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.99, green: 0.96, blue: 0.88),
                            Color(red: 0.91, green: 0.85, blue: 0.66),
                            Color(red: 0.72, green: 0.68, blue: 0.53),
                        ],
                        center: UnitPoint(x: 0.38, y: 0.38),
                        startRadius: 0,
                        endRadius: 28
                    )
                )
                .frame(width: 54, height: 54)
                .shadow(color: Color(red: 0.97, green: 0.93, blue: 0.78).opacity(0.25), radius: 28, x: 0, y: 0)
                .position(x: size.width * 0.89 - 27, y: 49)

            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.42),
                ],
                center: .center,
                startRadius: min(size.width, size.height) * 0.18,
                endRadius: max(size.width, size.height) * 0.68
            )
        }
    }

    private func forestLayer(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let x = size.width * (CGFloat(index) / 11.0)
                let height = size.height * (0.30 + CGFloat(index % 4) * 0.045)
                AchievementJourneyTreeShape()
                    .fill(Color(red: 0.03, green: 0.09, blue: 0.06).opacity(0.72))
                    .frame(width: 76 + CGFloat(index % 3) * 16, height: height)
                    .position(x: x, y: size.height - 96 - height * 0.22)
            }

            ForEach(0..<9, id: \.self) { index in
                let x = size.width * (CGFloat(index) / 8.0)
                let height = size.height * (0.36 + CGFloat(index % 3) * 0.055)
                AchievementJourneyTreeShape()
                    .fill(Color(red: 0.02, green: 0.07, blue: 0.05).opacity(0.90))
                    .frame(width: 96 + CGFloat(index % 2) * 24, height: height)
                    .position(x: x + CGFloat(index % 2) * 24 - 10, y: size.height - 74 - height * 0.20)
            }

            AchievementJourneySideTrunkShape()
                .fill(Color.black.opacity(0.22))
                .frame(width: 98, height: size.height * 0.72)
                .position(x: 18, y: size.height * 0.50)
            AchievementJourneySideTrunkShape()
                .fill(Color.black.opacity(0.20))
                .frame(width: 102, height: size.height * 0.76)
                .scaleEffect(x: -1, y: 1)
                .position(x: size.width - 16, y: size.height * 0.48)
        }
    }

    private func groundLayer(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.07),
                    Color(red: 0.04, green: 0.07, blue: 0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(116, size.height * 0.34))
        }
    }

    private func pathGroundLayer(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.22, green: 0.19, blue: 0.12).opacity(0.65),
                        Color(red: 0.13, green: 0.11, blue: 0.07).opacity(0.52),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.58
                )
            )
            .frame(width: size.width * 1.18, height: min(92, size.height * 0.28))
            .position(x: size.width * 0.50, y: size.height - 12)
            .blur(radius: 1)
            .opacity(0.65)
    }

    private func fireflyLayer(in size: CGSize, date: Date) -> some View {
        let time = CGFloat(date.timeIntervalSinceReferenceDate)

        return ZStack {
            ForEach(0..<fireflyPositions.count, id: \.self) { index in
                let base = fireflyPositions[index]
                let speed = CGFloat(0.42 + Double(index % 4) * 0.07)
                let driftX = sin(time * speed + CGFloat(index) * 1.7) * CGFloat(8 + (index % 3) * 4)
                let driftY = cos(time * (speed * 0.82) + CGFloat(index) * 1.3) * CGFloat(5 + (index % 2) * 4)
                let pulse = 0.42 + 0.42 * (sin(time * (speed * 2.2) + CGFloat(index)) + 1) / 2

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.34).opacity(0.42),
                                    Color(red: 1.0, green: 0.58, blue: 0.18).opacity(0.12),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 17
                            )
                        )
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.88, blue: 0.45).opacity(0.90))
                        .frame(width: 3.2, height: 3.2)
                }
                .opacity(pulse)
                .position(
                    x: size.width * base.x + driftX,
                    y: size.height * base.y + driftY
                )
            }
        }
    }

    private func unexploredFogLayer(in size: CGSize) -> some View {
        let clampedProgress = CGFloat(max(0, min(1, progress)))
        let width = size.width * max(0.18, 1 - clampedProgress + 0.08)
        let centerX = size.width - width / 2

        return LinearGradient(
            colors: [
                .clear,
                Color(red: 0.02, green: 0.04, blue: 0.04).opacity(0.52),
                Color(red: 0.02, green: 0.035, blue: 0.03).opacity(0.80),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: size.height)
        .position(x: centerX, y: size.height / 2)
    }

    private func routePath(in size: CGSize) -> Path {
        var path = Path()
        let p0 = CGPoint(x: size.width * 0.06, y: size.height * 0.72)
        let p1 = CGPoint(x: size.width * 0.30, y: size.height * 0.48)
        let p2 = CGPoint(x: size.width * 0.52, y: size.height * 0.76)
        let p3 = CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        let p4 = CGPoint(x: size.width * 0.94, y: size.height * 0.50)
        path.move(to: p0)
        path.addCurve(
            to: p1,
            control1: CGPoint(x: size.width * 0.14, y: size.height * 0.68),
            control2: CGPoint(x: size.width * 0.20, y: size.height * 0.44)
        )
        path.addCurve(
            to: p2,
            control1: CGPoint(x: size.width * 0.38, y: size.height * 0.42),
            control2: CGPoint(x: size.width * 0.40, y: size.height * 0.82)
        )
        path.addCurve(
            to: p3,
            control1: CGPoint(x: size.width * 0.59, y: size.height * 0.78),
            control2: CGPoint(x: size.width * 0.59, y: size.height * 0.60)
        )
        path.addCurve(
            to: p4,
            control1: CGPoint(x: size.width * 0.76, y: size.height * 0.42),
            control2: CGPoint(x: size.width * 0.82, y: size.height * 0.56)
        )
        return path
    }

    private func completedRoutePath(in size: CGSize) -> Path {
        var path = Path()
        let clampedProgress = CGFloat(max(0, min(1, progress)))
        path.move(to: routePoint(at: 0, in: size))
        let steps = max(2, Int(clampedProgress * 40))
        for step in 1...steps {
            let phase = clampedProgress * CGFloat(step) / CGFloat(steps)
            path.addLine(to: routePoint(at: phase, in: size))
        }
        return path
    }

    private func routePoint(at phase: CGFloat, in size: CGSize) -> CGPoint {
        let clamped = max(0, min(1, phase))
        let scaled = clamped * 4
        let segment = min(3, Int(scaled))
        let t = scaled - CGFloat(segment)

        let p0 = CGPoint(x: size.width * 0.06, y: size.height * 0.72)
        let p1 = CGPoint(x: size.width * 0.30, y: size.height * 0.48)
        let p2 = CGPoint(x: size.width * 0.52, y: size.height * 0.76)
        let p3 = CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        let p4 = CGPoint(x: size.width * 0.94, y: size.height * 0.50)

        switch segment {
        case 0:
            return cubic(
                t,
                p0,
                CGPoint(x: size.width * 0.14, y: size.height * 0.68),
                CGPoint(x: size.width * 0.20, y: size.height * 0.44),
                p1
            )
        case 1:
            return cubic(
                t,
                p1,
                CGPoint(x: size.width * 0.38, y: size.height * 0.42),
                CGPoint(x: size.width * 0.40, y: size.height * 0.82),
                p2
            )
        case 2:
            return cubic(
                t,
                p2,
                CGPoint(x: size.width * 0.59, y: size.height * 0.78),
                CGPoint(x: size.width * 0.59, y: size.height * 0.60),
                p3
            )
        default:
            return cubic(
                t,
                p3,
                CGPoint(x: size.width * 0.76, y: size.height * 0.42),
                CGPoint(x: size.width * 0.82, y: size.height * 0.56),
                p4
            )
        }
    }

    private func milestonePhase(_ index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0.50 }
        let start: CGFloat = 0.14
        let end: CGFloat = 0.82
        return start + (end - start) * CGFloat(index) / CGFloat(total - 1)
    }

    private func lanternBeam(
        from start: CGPoint,
        to end: CGPoint,
        farWidth: CGFloat,
        nearWidth: CGFloat,
        capDepth: CGFloat
    ) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let axis = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let nearCenter = CGPoint(x: start.x + axis.x * 4, y: start.y + axis.y * 4)
        let mid = CGPoint(x: start.x + dx * 0.56, y: start.y + dy * 0.56)
        let capCenter = CGPoint(x: end.x + axis.x * capDepth, y: end.y + axis.y * capDepth)
        let farTop = CGPoint(x: end.x + normal.x * farWidth, y: end.y + normal.y * farWidth)
        let farBottom = CGPoint(x: end.x - normal.x * farWidth, y: end.y - normal.y * farWidth)
        let nearTop = CGPoint(x: nearCenter.x + normal.x * nearWidth, y: nearCenter.y + normal.y * nearWidth)
        let nearBottom = CGPoint(x: nearCenter.x - normal.x * nearWidth, y: nearCenter.y - normal.y * nearWidth)

        var path = Path()
        path.move(to: nearTop)
        path.addCurve(
            to: farTop,
            control1: CGPoint(x: start.x + axis.x * 18 + normal.x * nearWidth * 1.4, y: start.y + axis.y * 18 + normal.y * nearWidth * 1.4),
            control2: CGPoint(x: mid.x + normal.x * farWidth * 0.94, y: mid.y + normal.y * farWidth * 0.94)
        )
        path.addCurve(
            to: farBottom,
            control1: CGPoint(x: capCenter.x + normal.x * farWidth * 0.28, y: capCenter.y + normal.y * farWidth * 0.28),
            control2: CGPoint(x: capCenter.x - normal.x * farWidth * 0.28, y: capCenter.y - normal.y * farWidth * 0.28)
        )
        path.addCurve(
            to: nearBottom,
            control1: CGPoint(x: mid.x - normal.x * farWidth * 0.94, y: mid.y - normal.y * farWidth * 0.94),
            control2: CGPoint(x: start.x + axis.x * 18 - normal.x * nearWidth * 1.4, y: start.y + axis.y * 18 - normal.y * nearWidth * 1.4)
        )
        path.closeSubpath()
        return path
    }

    private func lanternGlow(from start: CGPoint, to end: CGPoint) -> some View {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let point = CGPoint(x: end.x + dx / length * 13, y: end.y + dy / length * 13)
        let angle = Angle(radians: Double(atan2(dy, dx)) + .pi / 2)

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.83, blue: 0.35).opacity(0.44),
                            Color(red: 1.0, green: 0.56, blue: 0.18).opacity(0.22),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 38
                    )
                )
                .frame(width: 78, height: 54)
                .blur(radius: 3)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.76, blue: 0.32).opacity(0.20))
                .frame(width: 43, height: 28)
                .blur(radius: 7)
        }
        .rotationEffect(angle)
        .position(point)
    }

    private func cubic(_ t: CGFloat, _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x
        let y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

private struct AchievementJourneyTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let bottom = rect.maxY
        let trunkWidth = rect.width * 0.11
        let canopyWidth = rect.width

        path.addRoundedRect(
            in: CGRect(
                x: centerX - trunkWidth / 2,
                y: rect.minY + rect.height * 0.30,
                width: trunkWidth,
                height: rect.height * 0.70
            ),
            cornerSize: CGSize(width: trunkWidth * 0.35, height: trunkWidth * 0.35)
        )

        path.move(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.42, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.28, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.48, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.18, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.46, y: bottom * 0.92))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.46, y: bottom * 0.92))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.18, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.48, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.28, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.42, y: rect.minY + rect.height * 0.42))
        path.closeSubpath()

        return path
    }
}

private struct AchievementJourneySideTrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.height * 0.70),
            control2: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.height * 0.24)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY),
            control1: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.height * 0.30),
            control2: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.height * 0.74)
        )
        path.closeSubpath()
        return path
    }
}

private struct AchievementJourneyWalker: View {
    let frameIndex: Int

    var body: some View {
        ZStack {
            Image("HorongJourney\(min(max(frameIndex, 0), 2) + 1)")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
        }
        .frame(width: 88, height: 88)
    }
}

private struct AchievementJourneyDestination: View {
    let role: AchievementRole
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.035).opacity(0.86))
                if let imageURL, let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                } else {
                    Text(role.emoji)
                        .font(.system(size: 31))
                }
            }
            .frame(width: 70, height: 70)
            .overlay(Circle().stroke(Color(red: 0.66, green: 0.58, blue: 0.44).opacity(0.90), lineWidth: 3))
            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1).padding(5))
            .shadow(color: .black.opacity(0.48), radius: 11, x: 0, y: 7)

            Text("되고 싶은 나")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.80))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.48), in: Capsule())
        }
        .accessibilityLabel("되고 싶은 나, \(role.name)")
    }
}

private struct AchievementJourneyMilestone: View {
    let goal: AchievementGoal?
    let index: Int
    let isLit: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: goal == nil ? "flag" : "flag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(flagColor)
                .shadow(color: shadowColor, radius: 6, x: 0, y: 0)
            Text(goal?.title ?? "\(index + 1)번 목표")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(goal == nil ? .white.opacity(0.54) : .white.opacity(0.86))
                .lineLimit(1)
                .frame(width: 82)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
    }

    private var flagColor: Color {
        guard let goal else { return Color.white.opacity(0.36) }
        return isLit ? goal.color : Color.white.opacity(0.38)
    }

    private var shadowColor: Color {
        guard let goal, isLit else { return .clear }
        return goal.color.opacity(0.45)
    }
}

private struct AchievementJourneyStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

private struct AchievementJourneyActionStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isPrimary ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .fill(isPrimary ? PopoverChrome.primaryButtonFill : AnyShapeStyle(PopoverChrome.surfaceAlt))
            }
            .opacity(isPrimary ? 0.55 : 1)
            .buttonStyle(.plain)
    }
}

private extension View {
    func achievementJourneyActionStyle(isPrimary: Bool) -> some View {
        modifier(AchievementJourneyActionStyle(isPrimary: isPrimary))
    }
}

private struct AchievementSegmentedPicker<Value: CaseIterable & Identifiable & RawRepresentable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value
    let values: Value.AllCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values) { value in
                Button {
                    selection = value
                } label: {
                    Text(value.rawValue)
                        .font(.system(size: 12.5, weight: selection.rawValue == value.rawValue ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selection.rawValue == value.rawValue ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selection.rawValue == value.rawValue ? PopoverChrome.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

private struct AchievementMetricCard: View {
    let label: String
    let value: String
    let icon: String
    var valueSize: CGFloat = 18
    var isHighlighted = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isHighlighted ? PopoverChrome.accentInk : PopoverChrome.accent)
                .frame(width: 30, height: 30)
                .background(isHighlighted ? PopoverChrome.accent.opacity(0.92) : PopoverChrome.accentSoft.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isHighlighted ? PopoverChrome.inkSecondary : PopoverChrome.inkTertiary)
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
        .background(isHighlighted ? PopoverChrome.accentSoft.opacity(0.95) : PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                .stroke(isHighlighted ? PopoverChrome.accent.opacity(0.36) : PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
        .onTapGesture {
            onTap?()
        }
    }
}

private struct AchievementTimelineFilters: View {
    let goals: [AchievementGoal]
    @Binding var selectedGoalID: UUID?
    @Binding var selectedFilter: AchievementWeekGoalFilter
    let selectedGoal: AchievementGoal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AchievementWeekGoalFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 11.5, weight: selectedFilter == filter ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selectedFilter == filter ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? PopoverChrome.selectionFill : PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(goals) { goal in
                    Button {
                        selectedGoalID = goal.id
                        selectedFilter = .goal
                    } label: {
                        Text("\(goal.emoji) \(goal.title)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedGoal.emoji)
                    Text(selectedGoal.title)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AchievementGoalTimelineView: View {
    let items: [AchievementTimelineItem]
    let onMoveTodo: (UUID, Date) -> Void
    @State private var expandedItemIDs = Set<UUID>()

    private let columnWidth: CGFloat = 132
    private let axisY: CGFloat = 86
    private let firstTodoCenterOffset: CGFloat = 80
    private let todoBoxHeight: CGFloat = 54
    private let todoSpacing: CGFloat = 8
    private let moreButtonHeight: CGFloat = 28
    private let maxCollapsedTodoCount = 3

    private var todoStep: CGFloat {
        todoBoxHeight + todoSpacing
    }

    var body: some View {
        let totalWidth = CGFloat(items.count) * columnWidth
        let maxVisibleTodoCount = items.map(visibleTodoCount).max() ?? 0
        let hasMoreButton = items.contains { $0.todos.count > maxCollapsedTodoCount }
        let timelineHeight = max(
            CGFloat(220),
            axisY
                + firstTodoCenterOffset
                + CGFloat(max(0, maxVisibleTodoCount - 1)) * todoStep
                + todoBoxHeight / 2
                + (hasMoreButton ? todoSpacing + moreButtonHeight : 0)
                + 23
        )

        GeometryReader { geometry in
            let contentWidth = max(totalWidth, geometry.size.width)
            let resolvedColumnWidth = items.isEmpty ? columnWidth : contentWidth / CGFloat(items.count)

            ScrollView(.horizontal, showsIndicators: contentWidth > geometry.size.width) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isExpanded = expandedItemIDs.contains(item.id)
                        AchievementTimelineColumn(
                            item: item,
                            axisY: axisY,
                            firstTodoCenterOffset: firstTodoCenterOffset,
                            columnWidth: resolvedColumnWidth,
                            todoBoxHeight: todoBoxHeight,
                            todoSpacing: todoSpacing,
                            moreButtonHeight: moreButtonHeight,
                            maxCollapsedTodoCount: maxCollapsedTodoCount,
                            isExpanded: isExpanded,
                            height: timelineHeight - 10,
                            isLast: index == items.count - 1,
                            onToggleExpanded: {
                                if isExpanded {
                                    expandedItemIDs.remove(item.id)
                                } else {
                                    expandedItemIDs.insert(item.id)
                                }
                            },
                            onMoveTodo: onMoveTodo
                        )
                    }
                }
                .frame(width: contentWidth, height: timelineHeight - 10, alignment: .topLeading)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(height: timelineHeight + 8, alignment: .top)
        .accessibilityLabel("미리알림 할일 기반 주간 성취 타임라인")
    }

    private func visibleTodoCount(for item: AchievementTimelineItem) -> Int {
        if expandedItemIDs.contains(item.id) {
            return item.todos.count
        }
        return min(maxCollapsedTodoCount, item.todos.count)
    }
}

private struct AchievementTimelineColumn: View {
    let item: AchievementTimelineItem
    let axisY: CGFloat
    let firstTodoCenterOffset: CGFloat
    let columnWidth: CGFloat
    let todoBoxHeight: CGFloat
    let todoSpacing: CGFloat
    let moreButtonHeight: CGFloat
    let maxCollapsedTodoCount: Int
    let isExpanded: Bool
    let height: CGFloat
    let isLast: Bool
    let onToggleExpanded: () -> Void
    let onMoveTodo: (UUID, Date) -> Void
    @State private var isDropTargeted = false

    private var todoStep: CGFloat {
        todoBoxHeight + todoSpacing
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(width: columnWidth, height: 2)
                .position(x: columnWidth / 2, y: axisY)

            if isLast {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                    .position(x: columnWidth - 5, y: axisY)
            }

            if let topLabel = item.topLabel {
                AchievementTimelineBadge(label: topLabel, isReward: item.isReward)
                    .position(x: columnWidth / 2, y: axisY - 27)
            }

            AchievementTimelineNode(item: item)
                .position(x: columnWidth / 2, y: axisY)

            Text(item.weekday)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
                .position(x: columnWidth / 2, y: axisY + 25)

            if !item.todos.isEmpty {
                timelineConnectorSegments

                VStack(spacing: 8) {
                    ForEach(visibleTodos) { todo in
                        AchievementTimelineTodoBox(todo: todo)
                    }

                    if hiddenTodoCount > 0 || isExpanded {
                        Button {
                            onToggleExpanded()
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "접기" : "+\(hiddenTodoCount)개")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.accent)
                            .frame(width: 94, height: moreButtonHeight)
                            .background(PopoverChrome.accentSoft.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .position(x: columnWidth / 2, y: firstTodoCenterY + (todoStackHeight - todoBoxHeight) / 2)
            }
        }
        .frame(width: columnWidth, height: height)
        .contentShape(Rectangle())
        .background(isDropTargeted ? PopoverChrome.accentSoft.opacity(0.32) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous)
                .stroke(PopoverChrome.accent.opacity(isDropTargeted ? 0.58 : 0), lineWidth: 1.5)
        )
        .onDrop(of: [.text], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                return false
            }

            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? NSString,
                      let memoID = AchievementTimelineDragPayload.memoID(from: text as String) else { return }
                DispatchQueue.main.async {
                    onMoveTodo(memoID, item.date)
                }
            }
            return true
        }
    }

    private var connectorColor: Color {
        item.isCompleted ? PopoverChrome.accent.opacity(0.72) : PopoverChrome.inkTertiary.opacity(0.35)
    }

    private var firstTodoCenterY: CGFloat {
        axisY + firstTodoCenterOffset
    }

    private var visibleTodos: [AchievementTimelineTodo] {
        if isExpanded {
            return item.todos
        }
        return Array(item.todos.prefix(maxCollapsedTodoCount))
    }

    private var hiddenTodoCount: Int {
        max(0, item.todos.count - maxCollapsedTodoCount)
    }

    private var todoStackHeight: CGFloat {
        guard !visibleTodos.isEmpty else { return 0 }
        let todoHeight = CGFloat(visibleTodos.count) * todoBoxHeight
        let todoGapHeight = CGFloat(max(0, visibleTodos.count - 1)) * todoSpacing
        let toggleHeight = (hiddenTodoCount > 0 || isExpanded) ? todoSpacing + moreButtonHeight : 0
        return todoHeight + todoGapHeight + toggleHeight
    }

    private var timelineConnectorSegments: some View {
        let lineStartY = axisY + 36
        let firstTopY = firstTodoCenterY - todoBoxHeight / 2

        return ZStack(alignment: .topLeading) {
            connectorSegment(from: lineStartY, to: firstTopY)

            ForEach(0..<max(0, visibleTodos.count - 1), id: \.self) { index in
                let upperBottomY = firstTodoCenterY + CGFloat(index) * todoStep + todoBoxHeight / 2
                let lowerTopY = firstTodoCenterY + CGFloat(index + 1) * todoStep - todoBoxHeight / 2
                connectorSegment(from: upperBottomY, to: lowerTopY)
            }
        }
    }

    private func connectorSegment(from startY: CGFloat, to endY: CGFloat) -> some View {
        let segmentHeight = max(0, endY - startY)

        return Capsule()
            .fill(connectorColor)
            .frame(width: 2.5, height: segmentHeight)
            .position(x: columnWidth / 2, y: startY + segmentHeight / 2)
            .opacity(segmentHeight > 0 ? 1 : 0)
    }
}

private struct AchievementTimelineNode: View {
    let item: AchievementTimelineItem

    var body: some View {
        let hasSchedule = !item.todos.isEmpty || item.isReward || item.topLabel != nil

        ZStack {
            Circle()
                .fill(PopoverChrome.accent.opacity(item.isFuture ? 0.16 : 0.22))
                .frame(width: 22, height: 22)
            Circle()
                .fill(PopoverChrome.surface)
                .frame(width: 15, height: 15)
            Circle()
                .fill(hasSchedule ? PopoverChrome.accent.opacity(item.isFuture ? 0.74 : 1) : Color.clear)
                .frame(width: 8, height: 8)
        }
    }
}

private struct AchievementTimelineBadge: View {
    let label: String
    let isReward: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isReward ? "gift.fill" : "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isReward ? PopoverChrome.accentInk : PopoverChrome.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isReward ? PopoverChrome.accent : PopoverChrome.accentSoft, in: Capsule())
    }
}

private struct AchievementTimelineTodoBox: View {
    let todo: AchievementTimelineTodo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(todo.isCompleted ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                Text(todo.title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }
            if !todo.meta.isEmpty {
                Text(todo.meta)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: 94, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 54, alignment: .leading)
        .background(todo.isCompleted ? PopoverChrome.card : PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                .stroke(todo.isCompleted ? PopoverChrome.accent.opacity(0.55) : PopoverChrome.border, style: StrokeStyle(lineWidth: 1, dash: todo.isCompleted ? [] : [3, 3]))
        )
        .onDrag {
            NSItemProvider(object: AchievementTimelineDragPayload.string(for: todo.memoID) as NSString)
        }
    }
}

private struct AchievementDetailGoalRow: View {
    let goal: AchievementGoal
    let onAdd: () -> Void
    let onManage: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(goal.emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("\(goal.cadence) · \(goal.rule)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                AchievementRewardBadge(reward: goal.reward, color: goal.color)
                Menu {
                    Button {
                        onAdd()
                    } label: {
                        Label("할일 연결", systemImage: "link")
                    }
                    Button {
                        onManage()
                    } label: {
                        Label("수정", systemImage: "pencil")
                    }
                    Button("삭제", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            HStack(spacing: 10) {
                AchievementProgressBar(progress: goal.progress, color: goal.color)
                Text("\(goal.done)/\(goal.total)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
            }

            if !goal.todos.isEmpty {
                VStack(spacing: 6) {
                    ForEach(goal.todos) { todo in
                        HStack(spacing: 7) {
                            Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(todo.status == .done ? goal.color : PopoverChrome.inkTertiary)
                            Text(todo.text)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(todo.status == .done ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !todo.metaText.isEmpty {
                                Text(todo.metaText)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.inkTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .achievementDetailCard()
    }
}

private struct AchievementPeriodHeader: View {
    let title: String
    let subtitle: String
    let leading: String
    let trailing: String
    let onLeading: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        HStack {
            monthNavigationButton(title: leading, systemImage: "chevron.left", imagePlacement: .leading, action: onLeading)
            Spacer()
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            Spacer()
            monthNavigationButton(title: trailing, systemImage: "chevron.right", imagePlacement: .trailing, action: onTrailing)
        }
        .achievementDetailCard()
    }

    private enum NavigationImagePlacement {
        case leading
        case trailing
    }

    private func monthNavigationButton(
        title: String,
        systemImage: String,
        imagePlacement: NavigationImagePlacement,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if imagePlacement == .leading {
                    Image(systemName: systemImage)
                        .font(.system(size: 8.5, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                if imagePlacement == .trailing {
                    Image(systemName: systemImage)
                        .font(.system(size: 8.5, weight: .heavy))
                }
            }
            .foregroundStyle(PopoverChrome.accent)
            .frame(minWidth: 73, minHeight: 29)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                    .fill(PopoverChrome.accentSoft.opacity(0.72))
            )
            .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AchievementKRRow: View {
    let title: String
    let progress: Double
    var onManage: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }
            AchievementProgressBar(progress: progress, color: PopoverChrome.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onManage?()
        }
    }
}

private struct AchievementCalendarLegendButton: View {
    let goal: AchievementGoal
    let onManage: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onManage()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(goal.color)
                    .frame(width: 6, height: 6)
                Text(goal.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovered ? PopoverChrome.surfaceAlt : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("목표 관리")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct AchievementGoalManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: AchievementGoalRecord
    let linkedMemoCount: Int
    let memos: [Memo]
    let childRecords: [AchievementGoalRecord]
    let childCadence: String?
    let onSave: (AchievementGoalRecord, AchievementGoalEditDraft) -> Void
    let onDelete: (AchievementGoalRecord) -> Void
    let onAddChild: (AchievementGoalRecord, String, String) -> Void
    let onUpdateChild: (AchievementGoalRecord, String, String) -> Void
    let onDeleteChild: (AchievementGoalRecord) -> Void

    @State private var title: String
    @State private var emoji: String
    @State private var rule: String
    @State private var rewardText: String
    @State private var selectedMemoIDs: Set<UUID>
    @State private var newChildTitle = ""
    @State private var newChildEmoji = "🎯"
    @State private var showsDeleteConfirmation = false

    init(
        record: AchievementGoalRecord,
        linkedMemoCount: Int,
        memos: [Memo] = [],
        childRecords: [AchievementGoalRecord] = [],
        childCadence: String? = nil,
        onSave: @escaping (AchievementGoalRecord, AchievementGoalEditDraft) -> Void,
        onDelete: @escaping (AchievementGoalRecord) -> Void,
        onAddChild: @escaping (AchievementGoalRecord, String, String) -> Void = { _, _, _ in },
        onUpdateChild: @escaping (AchievementGoalRecord, String, String) -> Void = { _, _, _ in },
        onDeleteChild: @escaping (AchievementGoalRecord) -> Void = { _ in }
    ) {
        self.record = record
        self.linkedMemoCount = linkedMemoCount
        self.memos = memos
        self.childRecords = childRecords
        self.childCadence = childCadence
        self.onSave = onSave
        self.onDelete = onDelete
        self.onAddChild = onAddChild
        self.onUpdateChild = onUpdateChild
        self.onDeleteChild = onDeleteChild
        _title = State(initialValue: record.title)
        _emoji = State(initialValue: record.emoji)
        _rule = State(initialValue: record.rule)
        _rewardText = State(initialValue: record.rewardText)
        _selectedMemoIDs = State(initialValue: Set(record.linkedMemoIDs))
        _newChildEmoji = State(initialValue: AchievementGoalManagementSheet.defaultEmoji(for: childCadence))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("목표 관리")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text("\(record.cadence) · 연결된 할일 \(linkedMemoCount)개")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    field(label: "이모지") {
                        TextField("🎯", text: $emoji)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18))
                            .frame(width: 52)
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                            )
                    }
                    field(label: "목표명") {
                        TextField("목표명", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                            )
                    }
                }

                field(label: "달성 기준") {
                    TextField("예: 메모 3개 완료", text: $rule)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                }

                field(label: "보상") {
                    TextField("보상 없음", text: $rewardText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                                .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                }

                if childCadence != nil {
                    childGoalSection
                } else if supportsMemoLinks {
                    linkedMemoSection
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Text("삭제")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))

                Button {
                    onSave(record, AchievementGoalEditDraft(
                        title: title,
                        emoji: emoji,
                        rule: rule,
                        targetCount: supportsMemoLinks ? max(1, selectedMemoIDs.count) : record.targetCount,
                        rewardText: rewardText,
                        linkedMemoIDs: supportsMemoLinks ? Array(selectedMemoIDs) : nil
                    ))
                    dismiss()
                } label: {
                    Text("저장")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accentInk)
                .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(PopoverChrome.surface)
        .alert("목표를 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                onDelete(record)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 목표는 복구할 수 없습니다.")
        }
    }

    private var childGoalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("하위 \(childCadence ?? "") 목표")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(childRecords.count)개")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                TextField("📅", text: Binding(
                    get: { newChildEmoji },
                    set: { value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        newChildEmoji = trimmed.isEmpty ? Self.defaultEmoji(for: childCadence) : String(trimmed.prefix(1))
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .frame(width: 38)
                .padding(8)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

                TextField("\(childCadence ?? "") 목표 추가", text: $newChildTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .padding(8)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

                Button {
                    onAddChild(record, newChildTitle, newChildEmoji)
                    newChildTitle = ""
                    newChildEmoji = Self.defaultEmoji(for: childCadence)
                } label: {
                    Text("추가")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newChildTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newChildTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }

            if childRecords.isEmpty {
                Text("아직 연결된 \(childCadence ?? "") 목표가 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(childRecords, id: \.id) { child in
                            AchievementChildGoalEditorRow(
                                record: child,
                                onSave: onUpdateChild,
                                onDelete: onDeleteChild
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: childRecords.count > 3 ? 190 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.42), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
    }

    private var supportsMemoLinks: Bool {
        record.cadence == "주간"
    }

    private var linkedMemoSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("연결된 할일")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer()
                Text("\(selectedMemoIDs.count)개")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
            }

            if memos.isEmpty {
                Text("연결할 수 있는 할일이 없습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(memos) { memo in
                            Toggle(isOn: Binding(
                                get: { selectedMemoIDs.contains(memo.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedMemoIDs.insert(memo.id)
                                    } else {
                                        selectedMemoIDs.remove(memo.id)
                                    }
                                }
                            )) {
                                AchievementMemoPickerRow(memo: memo)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: memos.count > 4 ? 220 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.42), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
    }

    private static func defaultEmoji(for cadence: String?) -> String {
        switch cadence {
        case "연간": return "🏁"
        case "월간": return "📅"
        case "주간": return "🎯"
        default: return "🎯"
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
            content()
        }
    }
}

private struct AchievementChildGoalEditorRow: View {
    let record: AchievementGoalRecord
    let onSave: (AchievementGoalRecord, String, String) -> Void
    let onDelete: (AchievementGoalRecord) -> Void

    @State private var title: String
    @State private var emoji: String

    init(
        record: AchievementGoalRecord,
        onSave: @escaping (AchievementGoalRecord, String, String) -> Void,
        onDelete: @escaping (AchievementGoalRecord) -> Void
    ) {
        self.record = record
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: record.title)
        _emoji = State(initialValue: record.emoji)
    }

    var body: some View {
        HStack(spacing: 7) {
            TextField("📅", text: Binding(
                get: { emoji },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    emoji = trimmed.isEmpty ? "🎯" : String(trimmed.prefix(1))
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .frame(width: 34)
            .padding(7)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            TextField("목표명", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .padding(7)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            Button {
                onSave(record, title, emoji)
            } label: {
                Text("저장")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(minWidth: 44)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(PopoverChrome.accentSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                onDelete(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }
            .buttonStyle(.plain)
            .help("하위 목표 삭제")
        }
    }
}

private struct AchievementPersonaVisionComposerSheet: View {
    let personas: [AchievementRole]
    let selectedPersonaID: String
    let onClose: () -> Void
    let onSave: (AchievementPersonaVisionDraft) throws -> Void

    @State private var mode = "새 페르소나"
    @State private var selectedPersona = ""
    @State private var personaName = ""
    @State private var personaEmoji = "👤"
    @State private var visionTitle = ""
    @State private var visionEmoji = "🧭"
    @State private var validationMessage: String?
    @FocusState private var isPersonaEmojiFocused: Bool
    @FocusState private var isVisionEmojiFocused: Bool

    private let modes = ["새 페르소나", "기존 페르소나"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    modePicker

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    }

                    if mode == "새 페르소나" {
                        fieldLabel("페르소나")
                        emojiTextField(emoji: $personaEmoji, isFocused: $isPersonaEmojiFocused, placeholder: "이모지")
                        TextField("예: AI Engineer", text: $personaName)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                    } else {
                        fieldLabel("페르소나 선택")
                        Menu {
                            ForEach(personas) { persona in
                                Button {
                                    selectedPersona = persona.id
                                } label: {
                                    Text("\(persona.emoji) \(persona.name)")
                                }
                            }
                        } label: {
                            pickerLabel(selectedPersonaLabel)
                        }
                        .buttonStyle(.plain)
                    }

                    fieldLabel("비전")
                    emojiTextField(emoji: $visionEmoji, isFocused: $isVisionEmojiFocused, placeholder: "비전 이모지")
                    TextField("예: 사람들에게 쓰이는 생산성 제품을 만든다", text: $visionTitle)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
                .padding(14)
            }

            Button {
                save()
            } label: {
                Text("추가")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.48)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 360, height: 500)
        .background(PopoverChrome.surface)
        .onAppear {
            selectedPersona = selectedPersonaID.isEmpty ? personas.first?.id ?? "" : selectedPersonaID
            if personas.isEmpty {
                mode = "새 페르소나"
            } else if !selectedPersonaID.isEmpty {
                mode = "기존 페르소나"
            }
        }
    }

    private var header: some View {
        HStack {
            Text("페르소나/비전 추가")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button("닫기") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(PopoverChrome.surfaceAlt.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { item in
                Button {
                    mode = item
                    validationMessage = nil
                } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(mode == item ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mode == item ? PopoverChrome.accent : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item == "기존 페르소나" && personas.isEmpty)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private func emojiTextField(emoji: Binding<String>, isFocused: FocusState<Bool>.Binding, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji.wrappedValue)
                .font(.system(size: 20))
                .frame(width: 38, height: 36)
                .background(PopoverChrome.accentSoft, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

            TextField(placeholder, text: Binding(
                get: { emoji.wrappedValue },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    emoji.wrappedValue = trimmed.isEmpty ? "🎯" : String(trimmed.prefix(1))
                }
            ))
            .focused(isFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .frame(width: 64, height: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            Button {
                isFocused.wrappedValue = true
                DispatchQueue.main.async {
                    NSApplication.shared.orderFrontCharacterPalette(nil)
                }
            } label: {
                Label("이모지 선택", systemImage: "face.smiling")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
            .buttonStyle(.plain)
        }
    }

    private var selectedPersonaLabel: String {
        guard let persona = personas.first(where: { $0.id == selectedPersona }) else {
            return "페르소나 선택"
        }
        return "\(persona.emoji) \(persona.name)"
    }

    private var resolvedPersonaName: String {
        if mode == "새 페르소나" {
            return personaName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return personas.first(where: { $0.id == selectedPersona })?.name ?? ""
    }

    private var canSave: Bool {
        !resolvedPersonaName.isEmpty && !visionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        validationMessage = nil
        guard canSave else {
            validationMessage = "페르소나와 비전을 입력해 주세요."
            return
        }
        let personaEmojiValue = mode == "새 페르소나"
            ? personaEmoji
            : personas.first(where: { $0.id == selectedPersona })?.emoji ?? "👤"
        let draft = AchievementPersonaVisionDraft(
            personaName: resolvedPersonaName,
            personaEmoji: personaEmojiValue,
            visionTitle: visionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            visionText: visionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            visionEmoji: visionEmoji
        )
        do {
            try onSave(draft)
        } catch {
            validationMessage = "저장에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }
}

private struct AchievementEmptyDetailCard: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(message)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

private struct AchievementMemoPickerRow: View {
    let memo: Memo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(memo.icon ?? MemoIcon.defaultIcon)
                    .font(.system(size: 13))
                Text(memo.content)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(memo.isCompletedValue ? PopoverChrome.inkSecondary : PopoverChrome.ink)
                    .lineLimit(1)
            }
            let metaText = AchievementDataBuilder.todoMetaText(for: memo)
            if !metaText.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text(metaText)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
    }

    private var statusIcon: String {
        switch AchievementDataBuilder.todoStatus(for: memo) {
        case .done:
            return "checkmark.circle.fill"
        case .future:
            return "circle.dotted"
        case .pending:
            return "circle"
        }
    }

    private var statusColor: Color {
        switch AchievementDataBuilder.todoStatus(for: memo) {
        case .done:
            return PopoverChrome.accent
        case .future:
            return PopoverChrome.inkTertiary
        case .pending:
            return PopoverChrome.inkSecondary
        }
    }
}

private struct AchievementChildGoalPickerRow: View {
    let goal: AchievementGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(goal.emoji)
                    .font(.system(size: 13))
                Text(goal.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                Text("\(goal.done)/\(goal.total)")
                if !goal.rule.isEmpty {
                    Text(goal.rule)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
        }
    }
}

private struct AchievementMemoPickerSection: Identifiable {
    let icon: String
    let label: String
    let memos: [Memo]

    var id: String { icon }
}

private struct AchievementGoalComposerSheet: View {
    let memos: [Memo]
    let existingGoals: [AchievementGoal]
    let onClose: () -> Void
    let onSave: (AchievementGoalRecord, Set<UUID>) throws -> Void

    @AppStorage(Constants.AppStorageKey.achievementSuggestionCount)
    private var suggestionCount: Int = Constants.defaultAchievementSuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementSuggestionMaxTodoCount)
    private var suggestionMaxTodoCount: Int = Constants.defaultAchievementSuggestionMaxTodoCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionMinWeeklyGoalCount)
    private var monthlySuggestionMinWeeklyGoalCount: Int = Constants.defaultAchievementMonthlySuggestionMinWeeklyGoalCount
    @AppStorage(Constants.AppStorageKey.achievementMonthlySuggestionCount)
    private var monthlySuggestionCount: Int = Constants.defaultAchievementMonthlySuggestionCount
    @AppStorage(Constants.AppStorageKey.achievementSuggestionExcludedMemoIcons)
    private var excludedMemoIconsRaw: String = Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
    @AppStorage(Constants.AppStorageKey.achievementDismissedSuggestionKeys)
    private var dismissedSuggestionKeysRaw: String = ""

    @State private var selectedInputMode = "직접 입력"
    @State private var selectedTargetLevel = "주간"
    @State private var title = ""
    @State private var selectedEmoji = "🎯"
    @State private var selectedPersonaTitle = ""
    @State private var selectedVisionTitle = ""
    @State private var selectedChildGoalIDs = Set<UUID>()
    @State private var targetValueText = ""
    @State private var periodText = "이번 주"
    @State private var criterion = ""
    @State private var colorHex = "#E87333"
    @State private var selectedMemoIDs = Set<UUID>()
    @State private var validationMessage: String?
    @State private var suggestions: [AchievementGoalSuggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var suggestionMessage: String?
    @State private var didLoadSuggestions = false
    @State private var isAdvancedSettingsExpanded = false
    @State private var selectedPeriodDate = Date()
    @State private var expandedSuggestionKeys = Set<String>()
    @FocusState private var isEmojiInputFocused: Bool

    private let inputModes = ["AI 추천", "직접 입력"]
    private let targetLevels = ["역할", "비전", "월간", "주간"]
    private let colors = ["#E87333", "#2F5BEA", "#7A52D4", "#D94F73", "#2F9E73"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    modePicker
                    if selectedInputMode == "AI 추천" {
                        aiPlaceholder
                    } else {
                        directInputForm
                    }
                }
                .padding(14)
            }

            Button {
                save()
            } label: {
                Text("목표 만들기")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.48)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(PopoverChrome.surface)
        .onAppear {
            if !didLoadSuggestions {
                loadGoalSuggestions()
            }
        }
        .onChange(of: selectedInputMode) { _, mode in
            if mode == "AI 추천", !didLoadSuggestions {
                loadGoalSuggestions()
            }
        }
        .onChange(of: suggestionCount) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: suggestionMaxTodoCount) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: monthlySuggestionMinWeeklyGoalCount) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: monthlySuggestionCount) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
        .onChange(of: excludedMemoIconsRaw) { _, _ in
            reloadSuggestionsAfterSettingsChange()
        }
    }

    private var header: some View {
        HStack {
            Text("목표 추가")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button("닫기") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(PopoverChrome.surfaceAlt.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(inputModes, id: \.self) { mode in
                Button {
                    selectedInputMode = mode
                    validationMessage = nil
                } label: {
                    Text(mode)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedInputMode == mode ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedInputMode == mode ? PopoverChrome.accent : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private var aiPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("추천 묶음")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                    Text(suggestionMessage ?? "할일은 주간 목표로, 주간 목표는 월간 목표로 묶어 제안합니다.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    loadGoalSuggestions(force: true)
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingSuggestions {
                            ProgressView()
                                .scaleEffect(0.58)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(isLoadingSuggestions ? "추천 중" : "다시 추천")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(PopoverChrome.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoadingSuggestions)
                .help("다시 추천 받기")
            }

            if isLoadingSuggestions && suggestions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("묶을 수 있는 목표를 찾는 중")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else if suggestions.isEmpty {
                Text("추천할 묶음이 없습니다. 직접 입력에서 할일을 선택해 목표로 만들 수 있습니다.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                VStack(spacing: 9) {
                    ForEach(suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                }
            }

            Button {
                selectedInputMode = "직접 입력"
            } label: {
                Text("직접 할일 선택하기")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(PopoverChrome.accentSoft.opacity(0.68), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func suggestionCard(_ suggestion: AchievementGoalSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Text(suggestion.emoji)
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .background(PopoverChrome.accentSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(suggestion.title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .lineLimit(2)
                        Text(suggestion.target.rawValue)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(suggestion.target == .monthly ? PopoverChrome.accent : PopoverChrome.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                (suggestion.target == .monthly ? PopoverChrome.accentSoft : PopoverChrome.surfaceAlt).opacity(0.76),
                                in: Capsule()
                            )
                    }
                    Text(suggestion.reason)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button {
                    dismissSuggestion(suggestion)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 24, height: 24)
                        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("이 조합 추천 제외")
            }

            VStack(alignment: .leading, spacing: 5) {
                if suggestion.target == .monthly {
                    ForEach(visibleChildGoalIDs(for: suggestion), id: \.self) { id in
                        if let goal = goal(for: id) {
                            HStack(spacing: 6) {
                                Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "target")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(goal.isComplete ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                Text("\(goal.emoji) \(AchievementDataBuilder.shortText(goal.title, limit: 28))")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if suggestion.childGoalIDs.count > 3 {
                        Button {
                            toggleSuggestionExpansion(suggestion)
                        } label: {
                            Label(
                                isSuggestionExpanded(suggestion) ? "접기" : "외 \(suggestion.childGoalIDs.count - 3)개 주간 목표",
                                systemImage: isSuggestionExpanded(suggestion) ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(visibleMemoIDs(for: suggestion), id: \.self) { id in
                        if let memo = memo(for: id) {
                            HStack(spacing: 6) {
                                Image(systemName: memo.isCompletedValue ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(memo.isCompletedValue ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                                Text(AchievementDataBuilder.shortText(memo.content, limit: 30))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(PopoverChrome.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if suggestion.memoIDs.count > 3 {
                        Button {
                            toggleSuggestionExpansion(suggestion)
                        } label: {
                            Label(
                                isSuggestionExpanded(suggestion) ? "접기" : "외 \(suggestion.memoIDs.count - 3)개",
                                systemImage: isSuggestionExpanded(suggestion) ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(9)
            .background(PopoverChrome.surfaceAlt.opacity(0.58), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

            HStack(spacing: 8) {
                Label(suggestion.scheduleText, systemImage: "calendar")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    applySuggestion(suggestion)
                } label: {
                    Text("적용")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accentInk)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(11), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }

    private var directInputForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
            }

            fieldLabel("\(selectedTargetLevel) 목표")
            TextField(goalPlaceholder, text: $title)
                .textFieldStyle(.plain)
                .padding(10)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                        .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                )

            primarySourcePicker

            DisclosureGroup(isExpanded: $isAdvancedSettingsExpanded) {
                advancedSettingsForm
                    .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("고급 설정")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                        Text("비워두면 앱이 자동으로 채웁니다.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(11)
            .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
        }
    }

    @ViewBuilder
    private var primarySourcePicker: some View {
        if shouldShowMemoPicker {
            memoPicker
        } else {
            childGoalPicker
        }
    }

    private var advancedSettingsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("만들 대상")
            targetLevelGrid

            fieldLabel("이모지")
            emojiPicker

            if supportsPersonaVisionGroup {
                personaVisionPicker
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("목표 수치")
                    TextField(defaultTargetValueText, text: $targetValueText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("기간")
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedPeriodDate },
                            set: { date in
                                selectedPeriodDate = date
                                periodText = periodText(for: date)
                            }
                        ),
                        displayedComponents: .date
                    )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 10)
                        .frame(height: 36, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
            }

            fieldLabel("달성 기준")
            TextEditor(text: $criterion)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            colorPicker
        }
    }

    private var targetLevelGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(targetLevels, id: \.self) { level in
                Button {
                    selectedTargetLevel = level
                    selectedEmoji = emoji(for: level)
                    if level == "역할" {
                        selectedPersonaTitle = ""
                        selectedVisionTitle = ""
                    } else if level == "비전" {
                        selectedVisionTitle = ""
                    }
                    if !showsMemoPicker(for: level) {
                        selectedMemoIDs.removeAll()
                    }
                    selectedChildGoalIDs = selectedChildGoalIDs.filter { id in
                        childGoalCandidates(for: level).contains { $0.id == id }
                    }
                    if level == "주간" {
                        periodText = periodText.isEmpty ? "이번 주" : periodText
                    } else if level == "월간" {
                        periodText = periodText.isEmpty || periodText == "이번 주" ? "이번 달" : periodText
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(level)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        if let subtitle = targetLevelSubtitle(for: level) {
                            Text(subtitle)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                    }
                        .foregroundStyle(selectedTargetLevel == level ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(selectedTargetLevel == level ? PopoverChrome.accent : PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                                .stroke(selectedTargetLevel == level ? Color.clear : PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var personaVisionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(selectedTargetLevel == "비전" ? "페르소나 선택" : "페르소나/비전 묶음")

            HStack(spacing: 8) {
                Menu {
                    Button("선택 안함") {
                        selectedPersonaTitle = ""
                        selectedVisionTitle = ""
                    }
                    ForEach(personaGoals) { goal in
                        Button {
                            selectedPersonaTitle = goal.title
                            if selectedTargetLevel == "비전" {
                                selectedVisionTitle = ""
                            }
                            if !visionCandidates.contains(where: { $0.title == selectedVisionTitle }) {
                                selectedVisionTitle = ""
                            }
                        } label: {
                            Text("\(goal.emoji) \(goal.title)")
                        }
                    }
                } label: {
                    pickerLabel(selectedPersonaTitle.isEmpty ? "페르소나 없음" : selectedPersonaTitle)
                }
                .buttonStyle(.plain)

                if selectedTargetLevel != "비전" {
                    Menu {
                        Button("선택 안함") {
                            selectedVisionTitle = ""
                        }
                        ForEach(visionCandidates) { goal in
                            Button {
                                selectedVisionTitle = goal.title
                                if selectedPersonaTitle.isEmpty, !goal.roleName.isEmpty {
                                    selectedPersonaTitle = goal.roleName
                                }
                            } label: {
                                Text("\(goal.emoji) \(goal.title)")
                            }
                        }
                    } label: {
                        pickerLabel(selectedVisionTitle.isEmpty ? "비전 없음" : selectedVisionTitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var childGoalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let level = childGoalLevel {
                fieldLabel("하위 \(level) 목표")

                if childGoalCandidates.isEmpty {
                    Text("연결할 수 있는 \(level) 목표가 없습니다.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(childGoalCandidates) { goal in
                                Toggle(isOn: Binding(
                                    get: { selectedChildGoalIDs.contains(goal.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedChildGoalIDs.insert(goal.id)
                                            validationMessage = nil
                                        } else {
                                            selectedChildGoalIDs.remove(goal.id)
                                        }
                                    }
                                )) {
                                    AchievementChildGoalPickerRow(goal: goal)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: childGoalCandidates.count > 5 ? 230 : nil)
                    .popoverScrollbar()
                    .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                }
            }
        }
    }

    private var memoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("연결할 할일")

            if linkableMemos.isEmpty {
                Text("연결할 수 있는 미완료 할일이 없습니다. 먼저 메모장에서 할일을 추가해 주세요.")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(memoPickerSections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(section.icon)
                                        .font(.system(size: 12))
                                    Text(section.label)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.inkTertiary)
                                    Text("\(section.memos.count)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(PopoverChrome.inkTertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PopoverChrome.card.opacity(0.72), in: Capsule())
                                }

                                ForEach(section.memos) { memo in
                                    Toggle(isOn: Binding(
                                        get: { selectedMemoIDs.contains(memo.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedMemoIDs.insert(memo.id)
                                                validationMessage = nil
                                            } else {
                                                selectedMemoIDs.remove(memo.id)
                                            }
                                        }
                                    )) {
                                        AchievementMemoPickerRow(memo: memo)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: linkableMemos.count > 5 ? 230 : nil)
                .popoverScrollbar()
                .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
        }
    }

    private var emojiPicker: some View {
        HStack(spacing: 8) {
            Text(selectedEmoji)
                .font(.system(size: 20))
                .frame(width: 38, height: 36)
                .background(PopoverChrome.accentSoft, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))

            TextField("이모지", text: Binding(
                get: { selectedEmoji },
                set: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    selectedEmoji = trimmed.isEmpty ? "🎯" : String(trimmed.prefix(1))
                }
            ))
            .focused($isEmojiInputFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .frame(width: 64, height: 36)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))

            Button {
                isEmojiInputFocused = true
                DispatchQueue.main.async {
                    NSApplication.shared.orderFrontCharacterPalette(nil)
                }
            } label: {
                Label("이모지 선택", systemImage: "face.smiling")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
            }
            .buttonStyle(.plain)
            .help("macOS 문자 뷰어 열기")
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 7) {
            fieldLabel("색상")
            Spacer()
            ForEach(colors, id: \.self) { color in
                Button {
                    colorHex = color
                } label: {
                    Circle()
                        .fill(AchievementDataBuilder.color(from: color))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(colorHex == color ? PopoverChrome.ink : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestionSourceMemos: [Memo] {
        let weeklyLinkedIDs = Set(existingGoals.filter { $0.cadence == "주간" }.flatMap(\.sourceMemoIDs))
        return memos.filter { memo in
            !weeklyLinkedIDs.contains(memo.id)
                && !memo.isCompletedValue
                && isUsableSuggestionMemo(memo)
        }
    }

    private var linkableMemos: [Memo] {
        memos
            .filter { memo in
                let icon = memo.icon ?? MemoIcon.defaultIcon
                return !memo.isCompletedValue && !excludedMemoIcons.contains(icon)
            }
            .sorted(by: isMemoOrderedBefore)
    }

    private var memoPickerSections: [AchievementMemoPickerSection] {
        let iconRanks = Dictionary(uniqueKeysWithValues: MemoIcon.options.enumerated().map { ($0.element, $0.offset) })
        return Dictionary(grouping: linkableMemos, by: { $0.icon ?? MemoIcon.defaultIcon })
            .map { icon, memos in
                AchievementMemoPickerSection(
                    icon: icon,
                    label: MemoIcon.label(for: icon),
                    memos: memos.sorted(by: isMemoOrderedBefore)
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = iconRanks[lhs.icon] ?? Int.max
                let rhsRank = iconRanks[rhs.icon] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.label.localizedCompare(rhs.label) == .orderedAscending
            }
    }

    private func memoPickerDate(for memo: Memo) -> Date? {
        [memo.startDate, memo.deadline].compactMap { $0 }.max()
    }

    private func isMemoOrderedBefore(_ lhs: Memo, _ rhs: Memo) -> Bool {
        let lhsDate = memoPickerDate(for: lhs)
        let rhsDate = memoPickerDate(for: rhs)

        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.content.localizedCompare(rhs.content) == .orderedAscending
    }

    private var excludedMemoIcons: Set<String> {
        let raw = excludedMemoIconsRaw == Constants.legacyAchievementSuggestionExcludedMemoIconsRaw
            ? Constants.defaultAchievementSuggestionExcludedMemoIconsRaw
            : excludedMemoIconsRaw
        let icons = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { MemoIcon.options.contains($0) }
        return Set(icons)
    }

    private func isUsableSuggestionMemo(_ memo: Memo) -> Bool {
        let content = memo.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 3 else { return false }
        let icon = memo.icon ?? MemoIcon.defaultIcon
        if excludedMemoIcons.contains(icon) {
            return false
        }
        if icon == "🔗", content.localizedCaseInsensitiveContains("http") {
            return false
        }
        return true
    }

    private var weeklyGoalsForMonthlySuggestions: [AchievementGoal] {
        let weekly = existingGoals.filter { $0.cadence == "주간" }
        let unlinked = weekly.filter { ($0.monthGoal ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return unlinked
    }

    private var clampedSuggestionCount: Int {
        clamped(suggestionCount, in: Constants.achievementSuggestionCountRange)
    }

    private var clampedSuggestionMaxTodoCount: Int {
        clamped(suggestionMaxTodoCount, in: Constants.achievementSuggestionMaxTodoCountRange)
    }

    private var clampedMonthlyMinWeeklyGoalCount: Int {
        clamped(monthlySuggestionMinWeeklyGoalCount, in: Constants.achievementMonthlySuggestionMinWeeklyGoalCountRange)
    }

    private var clampedMonthlySuggestionCount: Int {
        clamped(monthlySuggestionCount, in: Constants.achievementMonthlySuggestionCountRange)
    }

    private func memo(for id: UUID) -> Memo? {
        memos.first { $0.id == id }
    }

    private func goal(for id: UUID) -> AchievementGoal? {
        existingGoals.first { $0.id == id }
    }

    private func loadGoalSuggestions(force: Bool = false) {
        guard force || !isLoadingSuggestions else { return }
        let snapshots = AchievementGoalSuggestionBuilder.snapshots(from: suggestionSourceMemos)
        let suggestionCount = clampedSuggestionCount
        let maxTodoCount = clampedSuggestionMaxTodoCount
        let weeklyGoalSnapshots = AchievementGoalSuggestionBuilder.snapshots(from: weeklyGoalsForMonthlySuggestions)
        let monthlyMinWeeklyCount = clampedMonthlyMinWeeklyGoalCount
        let monthlySuggestionCount = clampedMonthlySuggestionCount
        let shouldSuggestMonthly = weeklyGoalSnapshots.count >= monthlyMinWeeklyCount
        let ruleSuggestions = AchievementGoalSuggestionBuilder.ruleBasedSuggestions(
            from: snapshots,
            suggestionCount: suggestionCount,
            maxMemoCount: maxTodoCount
        )
        let monthlyRuleSuggestions = shouldSuggestMonthly
            ? AchievementGoalSuggestionBuilder.monthlyRuleBasedSuggestions(
                from: weeklyGoalSnapshots,
                suggestionCount: monthlySuggestionCount
            )
            : []

        suggestions = []
        suggestionMessage = shouldSuggestMonthly
            ? "할일과 주간 목표의 의미를 분석하고 있습니다."
            : "할일의 의미를 분석하고 있습니다."
        isLoadingSuggestions = true
        didLoadSuggestions = true

        Task {
            async let modelSuggestions = AchievementFoundationGoalSuggestionProvider.suggestions(
                from: snapshots,
                suggestionCount: suggestionCount,
                maxMemoCount: maxTodoCount
            )
            async let monthlyModelSuggestions = shouldSuggestMonthly
                ? AchievementFoundationGoalSuggestionProvider.monthlySuggestions(
                    from: weeklyGoalSnapshots,
                    suggestionCount: monthlySuggestionCount
                )
                : []
            let (weeklyModelValues, monthlyModelValues) = await (modelSuggestions, monthlyModelSuggestions)
            await MainActor.run {
                let weeklyModel = mergeSuggestions(
                    weeklyModelValues,
                    target: .weekly,
                    limit: suggestionCount
                )
                let monthlyModel = mergeSuggestions(
                    monthlyModelValues,
                    target: .monthly,
                    limit: monthlySuggestionCount
                )
                let weekly = weeklyModel.isEmpty
                    ? mergeSuggestions(ruleSuggestions, target: .weekly, limit: suggestionCount)
                    : weeklyModel
                let monthly = monthlyModel.isEmpty
                    ? mergeSuggestions(monthlyRuleSuggestions, target: .monthly, limit: monthlySuggestionCount)
                    : monthlyModel
                suggestions = weekly + monthly
                isLoadingSuggestions = false
                if weeklyModel.isEmpty && monthlyModel.isEmpty {
                    suggestionMessage = finalRuleSuggestionMessage(
                        weeklyCount: weekly.count,
                        monthlyCount: monthly.count,
                        shouldSuggestMonthly: shouldSuggestMonthly,
                        monthlyMinWeeklyCount: monthlyMinWeeklyCount
                    )
                } else {
                    suggestionMessage = "할일과 주간 목표의 의미를 보고 목표 초안을 만들었습니다."
                }
            }
        }
    }

    private func reloadSuggestionsAfterSettingsChange() {
        guard didLoadSuggestions else { return }
        expandedSuggestionKeys.removeAll()
        suggestions = []
        if selectedInputMode == "AI 추천" {
            loadGoalSuggestions(force: true)
        } else {
            didLoadSuggestions = false
            suggestionMessage = nil
        }
    }

    private func mergeSuggestions(_ values: [AchievementGoalSuggestion]) -> [AchievementGoalSuggestion] {
        let weekly = mergeSuggestions(values, target: .weekly, limit: clampedSuggestionCount)
        let monthly = mergeSuggestions(values, target: .monthly, limit: clampedMonthlySuggestionCount)
        return weekly + monthly
    }

    private func mergeSuggestions(
        _ values: [AchievementGoalSuggestion],
        target: AchievementGoalSuggestionTarget,
        limit: Int
    ) -> [AchievementGoalSuggestion] {
        var seen = Set<Set<UUID>>()
        var result: [AchievementGoalSuggestion] = []
        for suggestion in values where suggestion.target == target {
            guard isAcceptableSuggestion(suggestion) else { continue }
            let keyIDs = target == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs
            guard keyIDs.count >= 2 else { continue }
            guard !dismissedSuggestionKeys.contains(suggestionKey(for: suggestion)) else { continue }
            let key = Set(keyIDs)
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
        }
        return Array(result.prefix(limit))
    }

    private func dismissSuggestion(_ suggestion: AchievementGoalSuggestion) {
        let key = suggestionKey(for: suggestion)
        var keys = dismissedSuggestionKeys
        keys.insert(key)
        dismissedSuggestionKeysRaw = encodeDismissedSuggestionKeys(keys)
        expandedSuggestionKeys.remove(key)
        suggestions.removeAll { suggestionKey(for: $0) == key }
        if suggestions.isEmpty {
            suggestionMessage = "제외하지 않은 추천 묶음이 없습니다. 다시 추천을 받아볼 수 있습니다."
        }
    }

    private var dismissedSuggestionKeys: Set<String> {
        Set(dismissedSuggestionKeysRaw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private func encodeDismissedSuggestionKeys(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: "\n")
    }

    private func visibleMemoIDs(for suggestion: AchievementGoalSuggestion) -> [UUID] {
        isSuggestionExpanded(suggestion) ? suggestion.memoIDs : Array(suggestion.memoIDs.prefix(3))
    }

    private func visibleChildGoalIDs(for suggestion: AchievementGoalSuggestion) -> [UUID] {
        isSuggestionExpanded(suggestion) ? suggestion.childGoalIDs : Array(suggestion.childGoalIDs.prefix(3))
    }

    private func isSuggestionExpanded(_ suggestion: AchievementGoalSuggestion) -> Bool {
        expandedSuggestionKeys.contains(suggestionKey(for: suggestion))
    }

    private func toggleSuggestionExpansion(_ suggestion: AchievementGoalSuggestion) {
        let key = suggestionKey(for: suggestion)
        if expandedSuggestionKeys.contains(key) {
            expandedSuggestionKeys.remove(key)
        } else {
            expandedSuggestionKeys.insert(key)
        }
    }

    private func suggestionKey(for suggestion: AchievementGoalSuggestion) -> String {
        let ids = (suggestion.target == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs)
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(suggestion.target.rawValue):\(ids)"
    }

    private func isAcceptableSuggestion(_ suggestion: AchievementGoalSuggestion) -> Bool {
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 4 else { return false }

        let lowercasedTitle = title.lowercased()
        let blockedTitles = [
            "markdown 목표",
            "kakaotalk 목표",
            "obsidian 목표",
            "링크 정리 목표",
        ]
        if blockedTitles.contains(where: { lowercasedTitle.contains($0) }) {
            return false
        }

        let keyIDs = suggestion.target == .monthly ? suggestion.childGoalIDs : suggestion.memoIDs
        return Set(keyIDs).count >= 2
    }

    private func applySuggestion(_ suggestion: AchievementGoalSuggestion) {
        selectedInputMode = "직접 입력"
        selectedTargetLevel = suggestion.target.cadence
        selectedEmoji = suggestion.emoji
        title = suggestion.title
        selectedMemoIDs = suggestion.target == .weekly ? Set(suggestion.memoIDs) : []
        selectedChildGoalIDs = suggestion.target == .monthly ? Set(suggestion.childGoalIDs) : []
        applyCommonHierarchy(from: suggestion)
        targetValueText = suggestion.targetValueText
        periodText = suggestion.target.periodText
        criterion = suggestion.criterion
        validationMessage = nil
    }

    private func applyCommonHierarchy(from suggestion: AchievementGoalSuggestion) {
        guard suggestion.target == .monthly else { return }
        let childGoals = existingGoals.filter { suggestion.childGoalIDs.contains($0.id) }
        if let roleName = commonNonEmpty(childGoals.map(\.roleName)) {
            selectedPersonaTitle = roleName
        }
        if let vision = commonNonEmpty(childGoals.map(\.vision)) {
            selectedVisionTitle = vision
        }
    }

    private func commonNonEmpty(_ values: [String]) -> String? {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = trimmed.first, trimmed.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func initialSuggestionMessage(weeklyCount: Int, monthlyCount: Int, shouldSuggestMonthly: Bool) -> String {
        if weeklyCount == 0 && monthlyCount == 0 {
            return shouldSuggestMonthly
                ? "직접 선택할 수 있는 목표는 있지만 자동 묶음은 아직 없습니다."
                : "주간 목표가 더 쌓이면 월간 목표 추천도 함께 보여줍니다."
        }
        if monthlyCount > 0 {
            return "할일 묶음과 주간 목표 묶음을 함께 만들었습니다."
        }
        return "비슷한 할일을 묶어 주간 목표 초안을 만들었습니다."
    }

    private func finalRuleSuggestionMessage(
        weeklyCount: Int,
        monthlyCount: Int,
        shouldSuggestMonthly: Bool,
        monthlyMinWeeklyCount: Int
    ) -> String {
        if weeklyCount == 0 && monthlyCount == 0 {
            return shouldSuggestMonthly
                ? "추천할 묶음이 없습니다. 직접 목표를 선택해 만들 수 있습니다."
                : "주간 목표가 \(monthlyMinWeeklyCount)개 이상 쌓이면 월간 목표도 추천합니다."
        }
        if monthlyCount > 0 {
            return "할일과 주간 목표를 묶어 목표 초안을 만들었습니다."
        }
        return "비슷한 할일을 묶어 주간 목표 초안을 만들었습니다."
    }

    private var canSave: Bool {
        selectedInputMode == "직접 입력"
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (allowsSavingWithoutLinkedSource || !selectedLinkableMemoIDs.isEmpty || !selectedChildGoalIDs.isEmpty)
    }

    private var supportsPersonaVisionGroup: Bool {
        ["비전", "월간", "주간"].contains(selectedTargetLevel)
    }

    private var allowsSavingWithoutLinkedSource: Bool {
        ["역할", "비전"].contains(selectedTargetLevel)
    }

    private var shouldShowMemoPicker: Bool {
        showsMemoPicker(for: selectedTargetLevel)
    }

    private var personaGoals: [AchievementGoal] {
        existingGoals.filter { $0.cadence == "역할" }
    }

    private var visionCandidates: [AchievementGoal] {
        existingGoals.filter { goal in
            guard goal.cadence == "비전" else { return false }
            return selectedPersonaTitle.isEmpty || goal.roleName == selectedPersonaTitle
        }
    }

    private var selectedPersonaGoal: AchievementGoal? {
        personaGoals.first { $0.title == selectedPersonaTitle }
    }

    private var selectedVisionGoal: AchievementGoal? {
        existingGoals.first { $0.cadence == "비전" && $0.title == selectedVisionTitle }
    }

    private var childGoalLevel: String? {
        childGoalLevel(for: selectedTargetLevel)
    }

    private var childGoalCandidates: [AchievementGoal] {
        childGoalCandidates(for: selectedTargetLevel)
    }

    private func childGoalLevel(for level: String) -> String? {
        switch level {
        case "비전":
            return "월간"
        case "월간":
            return "주간"
        default:
            return nil
        }
    }

    private func childGoalCandidates(for level: String) -> [AchievementGoal] {
        guard let childLevel = childGoalLevel(for: level) else { return [] }
        return existingGoals.filter { goal in
            guard goal.cadence == childLevel else {
                return false
            }
            if !selectedPersonaTitle.isEmpty, goal.roleName != selectedPersonaTitle {
                return false
            }
            if !selectedVisionTitle.isEmpty, goal.vision != selectedVisionTitle {
                return false
            }
            return true
        }
    }

    private var defaultTargetValueText: String {
        "\(max(1, selectedSourceCount))개"
    }

    private var selectedSourceCount: Int {
        if shouldShowMemoPicker {
            return selectedLinkableMemoIDs.count
        }
        return selectedChildGoalIDs.count
    }

    private var selectedLinkableMemoIDs: Set<UUID> {
        selectedMemoIDs.intersection(Set(linkableMemos.map(\.id)))
    }

    private func defaultPeriodText(for level: String) -> String {
        switch level {
        case "월간":
            return "이번 달"
        case "주간":
            return "이번 주"
        case "비전":
            return "장기"
        default:
            return "계속"
        }
    }

    private func periodText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일까지"
        return formatter.string(from: date)
    }

    private func defaultCriterionText(for level: String, linkedMemoCount: Int, childGoalCount: Int) -> String {
        switch level {
        case "월간":
            return "연결한 주간 목표 \(max(1, childGoalCount))개 달성"
        case "비전":
            return childGoalCount > 0 ? "연결한 월간 목표 \(childGoalCount)개 달성" : "비전 방향 유지"
        case "역할":
            return "페르소나 방향 유지"
        default:
            return "연결한 할일 \(max(1, linkedMemoCount))개 완료"
        }
    }

    private var goalPlaceholder: String {
        switch selectedTargetLevel {
        case "역할": return "예: AI 엔지니어"
        case "비전": return "예: RAG 제품을 출시한다"
        case "월간": return "예: 검색 품질 개선"
        default: return "예: 딥워크 주 5시간"
        }
    }

    private func targetLevelSubtitle(for level: String) -> String? {
        switch level {
        case "역할":
            return "(페르소나)"
        case "비전":
            return "(지향점)"
        default:
            return nil
        }
    }

    private var breadcrumbText: String {
        targetLevels.joined(separator: " · ")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }

    private func save() {
        validationMessage = nil
        guard selectedInputMode == "직접 입력" else {
            validationMessage = "AI 추천은 아직 준비 중입니다. 직접 입력으로 등록해 주세요."
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "\(selectedTargetLevel) 목표를 입력해 주세요."
            return
        }
        guard allowsSavingWithoutLinkedSource || !selectedLinkableMemoIDs.isEmpty || !selectedChildGoalIDs.isEmpty else {
            validationMessage = "연결할 하위 목표나 할 일을 하나 이상 선택해 주세요."
            return
        }
        let trimmedTitle = AchievementDataBuilder.shortText(title, limit: 40)
        let childGoals = existingGoals.filter { selectedChildGoalIDs.contains($0.id) }
        let linkedMemoIDs = Array(selectedLinkableMemoIDs.union(childGoals.flatMap(\.sourceMemoIDs)))
        let hierarchy = hierarchyValues(title: trimmedTitle)
        let resolvedTargetValueText = optionalText(targetValueText) ?? defaultTargetValueText
        let resolvedPeriodText = optionalText(periodText) ?? defaultPeriodText(for: selectedTargetLevel)
        let resolvedCriterion = optionalText(criterion) ?? defaultCriterionText(
            for: selectedTargetLevel,
            linkedMemoCount: linkedMemoIDs.count,
            childGoalCount: selectedChildGoalIDs.count
        )
        let record = AchievementGoalRecord(
            title: trimmedTitle,
            emoji: selectedEmoji,
            cadence: selectedTargetLevel,
            rule: resolvedCriterion,
            targetCount: max(1, linkedMemoIDs.count),
            targetValueText: resolvedTargetValueText,
            periodText: resolvedPeriodText,
            rewardText: "",
            colorHex: colorHex,
            roleName: hierarchy.roleName,
            vision: hierarchy.vision,
            yearGoal: hierarchy.yearGoal,
            quarterGoal: nil,
            monthGoal: hierarchy.monthGoal,
            linkedMemoIDs: linkedMemoIDs
        )
        do {
            try onSave(record, selectedChildGoalIDs)
            onClose()
        } catch {
            validationMessage = "목표 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func hierarchyValues(title: String) -> (roleName: String, vision: String, yearGoal: String?, monthGoal: String?) {
        let roleName = selectedPersonaGoal?.title ?? selectedVisionGoal?.roleName ?? ""
        let vision = selectedVisionGoal?.title ?? ""

        switch selectedTargetLevel {
        case "역할":
            return (title, "", nil, nil)
        case "비전":
            return (selectedPersonaGoal?.title ?? "", title, nil, nil)
        case "월간":
            return (roleName, vision, nil, nil)
        default:
            return (roleName, vision, nil, nil)
        }
    }

    private func emoji(for level: String) -> String {
        switch level {
        case "역할": return "👤"
        case "비전": return "🧭"
        case "월간": return "📅"
        default: return "🎯"
        }
    }

    private func showsMemoPicker(for level: String) -> Bool {
        level == "주간"
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private extension View {
    func achievementDetailCard() -> some View {
        self
            .padding(14)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
    }
}
