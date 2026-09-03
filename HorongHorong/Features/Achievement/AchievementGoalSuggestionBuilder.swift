import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 목표 추천의 후보를 고른다.
 
  앱 설정을 적용해 할일·주간 목표를 거르고 스냅샷으로 만든다.
 
  **이 파일의 책임이 아닌 것**: 프롬프트 구성·입력 예산 적용·모델 응답 JSON 파싱과 검증은
  `HorongAI` 의 `WeeklyGoalTask`·`MonthlyGoalTask` 가 한다.
 
  추천 정책이 화면 상태와 무관해지거나 다른 기능에서도 쓰이게 되면 여기 쌓지 말고
  `Domain/Policies` 또는 `HorongAI` 로 옮긴다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementGoalSuggestionBuilder {
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

    static func snapshots(from memos: [AchievementMemoDetail]) -> [AchievementMemoSnapshot] {
        memos.map { memo in
            AchievementMemoSnapshot(
                id: memo.id,
                content: memo.content,
                icon: memo.icon,
                date: memo.date,
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompleted
            )
        }
    }

    /// 파일이 갈리면서 `fileprivate` 로는 안 보이게 됐다. 목표 작성 시트가 부른다.
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
        suggestionCount: Int,
        maxGoalsPerSuggestion: Int
    ) -> [AchievementGoalSuggestion] {
        let candidates = goals.filter { goal in
            goal.monthGoal?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        let source = candidates.count >= 2 ? candidates : goals
        var suggestions: [AchievementGoalSuggestion] = []

        suggestions.append(contentsOf: groupedMonthlyByContext(from: source, maxGoalsPerSuggestion: maxGoalsPerSuggestion))
        suggestions.append(contentsOf: groupedMonthlyByKeyword(from: source, maxGoalsPerSuggestion: maxGoalsPerSuggestion))
        suggestions.append(contentsOf: groupedMonthlyFallback(from: source, maxGoalsPerSuggestion: maxGoalsPerSuggestion))

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

    private static func groupedMonthlyByContext(from goals: [AchievementGoalSnapshot], maxGoalsPerSuggestion: Int) -> [AchievementGoalSuggestion] {
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
            let limited = limitedGoals(items, maxGoalsPerSuggestion: maxGoalsPerSuggestion)
            return monthlySuggestion(
                title: monthlyTitle(for: limited, context: key),
                reason: "같은 페르소나나 비전으로 이어지는 주간 목표 \(limited.count)개를 묶었습니다.",
                goals: limited,
                emoji: limited.first?.emoji ?? "📅",
                source: .rule,
                ruleName: "context"
            )
        }
    }

    private static func groupedMonthlyByKeyword(from goals: [AchievementGoalSnapshot], maxGoalsPerSuggestion: Int) -> [AchievementGoalSuggestion] {
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
            let limited = limitedGoals(items, maxGoalsPerSuggestion: maxGoalsPerSuggestion)
            return monthlySuggestion(
                title: monthlyTitle(for: limited),
                reason: "비슷한 방향의 주간 목표 \(limited.count)개를 한 달 목표로 묶었습니다.",
                goals: limited,
                emoji: group.emoji,
                source: .rule,
                ruleName: "keyword"
            )
        }
    }

    private static func groupedMonthlyFallback(from goals: [AchievementGoalSnapshot], maxGoalsPerSuggestion: Int) -> [AchievementGoalSuggestion] {
        guard goals.count >= 2 else { return [] }
        let limited = limitedGoals(goals, maxGoalsPerSuggestion: maxGoalsPerSuggestion)
        return [
            monthlySuggestion(
                title: monthlyTitle(for: limited),
                reason: "이번 달에 함께 밀어야 할 주간 목표 \(limited.count)개를 묶었습니다.",
                goals: limited,
                emoji: "📅",
                source: .rule,
                ruleName: "fallback"
            ),
        ]
    }

    private static func monthlySuggestion(
        title: String,
        reason: String,
        goals: [AchievementGoalSnapshot],
        emoji: String,
        source: AchievementGoalSuggestionSource,
        ruleName: String? = nil
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
            cadence: .monthly,
            source: source,
            ruleName: ruleName
        )
    }

    private static func limitedGoals(_ goals: [AchievementGoalSnapshot], maxGoalsPerSuggestion: Int) -> [AchievementGoalSnapshot] {
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
        }.prefix(maxGoalsPerSuggestion))
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
