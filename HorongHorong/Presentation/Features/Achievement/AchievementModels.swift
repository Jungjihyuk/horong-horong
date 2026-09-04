import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 성취 화면이 쓰는 값 타입들.
 
  목표·할일·역할과 타임라인 항목, 편집 중 초안. 저장은 `AchievementGoalRecord` 등
  `@Model` 이 하고, 이 타입들은 화면이 한 번의 렌더에서 쓰는 모습으로 추린 것이다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementTodoStatus {
    case done
    case pending
    case future
}

struct AchievementReward {
    /// 보상 문구를 적지 않은 목표. 이 값이면 배지를 띄우지 않는다.
    static let emptyAmount = "보상 없음"

    let amount: String
}

struct AchievementTodo: Identifiable {
    let id: UUID
    let text: String
    let when: String
    let detail: String
    let status: AchievementTodoStatus

    var metaText: String {
        when.isEmpty ? detail : "\(when) · \(detail)"
    }
}

struct AchievementGoal: Identifiable {
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
    let createdAt: Date
    let dueDate: Date?
    let sourceMemoIDs: [UUID]
    /// 못 이룬 채 닫힌 순간. 열려 있으면 nil.
    let closedAt: Date?
    /// 왜 닫혔나. 배지 문구와 되돌리기 안내가 갈린다.
    let closedReason: AchievementCloseReason?

    /// 못 이룬 채 닫혔는가. 「기한 지남」 배지 대신 「실패 마감」 배지를 다는 기준이다.
    var isClosedUnfinished: Bool { closedAt != nil }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    /// 달성 여부.
    ///
    /// `total` 이 0 이면 연결된 할일이 없다는 뜻이라 달성이 아니다.
    /// 가드가 없으면 `0 >= 0` 이 참이 되어 빈 목표가 달성으로 잡힌다.
    var isComplete: Bool {
        total > 0 && done >= total
    }

    /// 마감일을 지정했고, 그 날이 지났는데 아직 끝내지 못한 상태.
    var isOverdue: Bool {
        // 이미 닫힌 목표는 «기한 지남» 이 아니다 — 답이 나왔으므로 질문이 끝났다.
        guard closedAt == nil else { return false }
        guard let dueDate, !(total > 0 && done >= total) else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date())
    }

    var dueDateText: String? {
        guard let dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: dueDate)
    }

    var nextTodo: AchievementTodo? {
        todos.first { $0.status == .pending } ?? todos.first
    }
}

/// 목표 하나가 할일을 독점한다는 규칙(`AchievementMemoLinkPolicy`)에 화면 타입도 그대로 넣는다.
/// 하위 목표에서 올라온 할일까지 포함한 `sourceMemoIDs` 가 이 목표가 «가진» 할일이다.
extension AchievementGoal: AchievementLinkableGoal {
    var linkedMemoIDs: [UUID] { sourceMemoIDs }
}

struct AchievementRole: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let vision: String
}

struct AchievementTimelineItem: Identifiable {
    let id = UUID()
    let date: Date
    let weekday: String
    let topLabel: String?
    let todos: [AchievementTimelineTodo]
    let isCompleted: Bool
    let isFuture: Bool
    let isReward: Bool
}

struct AchievementTimelineTodo: Identifiable {
    let id: UUID
    let memoID: UUID
    let title: String
    let meta: String
    let isCompleted: Bool
    let isFuture: Bool
    /// 화면에 그리지 않고 정렬에만 쓰는 기준 시각. `startDate ?? deadline`.
    let sortDate: Date?
    /// 시작 시각 없이 마감만 있는 일은 «그 날 안에 언제든» 이라 칸 아래로 내린다.
    let hasStartTime: Bool
}

enum AchievementTimelineDragPayload {
    static let prefix = "horong-achievement-memo:"

    static func string(for memoID: UUID) -> String {
        "\(prefix)\(memoID.uuidString)"
    }

    static func memoID(from text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }
}

struct AchievementGoalEditDraft {
    let title: String
    let emoji: String
    let rule: String
    let targetCount: Int
    let rewardText: String
    let linkedMemoIDs: [UUID]?
    var dueDate: Date?
    let additionalChildGoalIDs: [UUID]?
}

struct AchievementPersonaVisionDraft {
    let personaName: String
    let personaEmoji: String
    let visionTitle: String
    let visionText: String
    let visionEmoji: String
}
