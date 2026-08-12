import Foundation

/// 할일 목록을 주고 **주간 목표 후보**를 받아오는 태스크.
///
/// 프롬프트 만들기 · 입력 고르기(예산) · 응답 읽기를 한 자리에 둔다. 셋은 함께 바뀐다 —
/// 프롬프트의 JSON 형식을 고치면 파서도 같이 고쳐야 하기 때문이다.
///
/// 공급자(AFM · MLX · Ollama)를 가리지 않는다. 셋 다 같은 프롬프트·파서를 써야
/// 골든셋에서 모델끼리 공정하게 비교된다.
public enum WeeklyGoalTask {

    /// 프롬프트에 실리는 할일 하나.
    ///
    /// 앱의 저장 모델을 그대로 받지 않는 이유는 패키지가 앱 도메인 타입을 알면 안 되기 때문이다.
    /// 아이콘 기본값처럼 **앱이 정하는 값**은 경계를 넘기 전에 앱이 채워 넣는다.
    public struct Memo: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let content: String
        public let icon: String
        public let date: Date
        public let startDate: Date?
        public let deadline: Date?
        public let isCompleted: Bool

        public init(
            id: UUID,
            content: String,
            icon: String,
            date: Date,
            startDate: Date? = nil,
            deadline: Date? = nil,
            isCompleted: Bool = false
        ) {
            self.id = id
            self.content = content
            self.icon = icon
            self.date = date
            self.startDate = startDate
            self.deadline = deadline
            self.isCompleted = isCompleted
        }
    }

    // MARK: - 입력 고르기

    /// 프롬프트가 문자 예산을 넘지 않는 선까지만 메모를 담는다.
    /// 메모 길이는 사용자마다 제각각이라 "개수" 상한만으로는 크기를 보장할 수 없다.
    ///
    /// 예산은 공급자마다 다르므로(AFM 4,000 · MLX/Ollama 16,000) 태스크가 정하지 않고 받는다.
    public static func memosWithinPromptBudget(
        _ memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int,
        budget: Int
    ) -> [Memo] {
        // 묶으려면 최소 2개는 있어야 하므로 예산을 넘더라도 2개는 유지한다.
        let minimumCount = min(2, memos.count)
        var selected = memos
        while selected.count > minimumCount {
            let size = prompt(
                for: selected,
                suggestionCount: suggestionCount,
                maxMemoCount: maxMemoCount
            ).count
            if size <= budget { break }
            selected.removeLast()
        }
        return selected
    }

    // MARK: - 프롬프트

    public static func prompt(
        for memos: [Memo],
        suggestionCount: Int,
        maxMemoCount: Int
    ) -> String {
        // 프롬프트 크기가 추론 성패를 가르므로(인시던트 2026-07-31) 값이 없는 필드는 생략한다.
        // "없음"으로 채우면 메모당 30자 이상을 정보 없이 소비한다.
        let lines = memos.map { memo in
            var fields = [
                "- id: \(memo.id.uuidString)",
                "  text: \(memo.content)",
                "  icon: \(memo.icon)",
                "  date: \(dateText(memo.date))",
            ]
            if memo.startDate != nil {
                fields.append("  startDate: \(dateText(memo.startDate))")
            }
            if memo.deadline != nil {
                fields.append("  deadline: \(dateText(memo.deadline))")
            }
            // 미완료 할일만 입력으로 들어오므로 기본값일 때는 생략한다.
            if memo.isCompleted {
                fields.append("  completed: true")
            }
            return fields.joined(separator: "\n")
        }.joined(separator: "\n")

        return PromptRenderer.render(
            fileName: "weekly_goal",
            fallback: promptFallback,
            values: [
                "suggestionCount": "\(suggestionCount)",
                "maxMemoCount": "\(maxMemoCount)",
                "items": lines,
            ]
        )
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd E HH:mm"
        return formatter.string(from: date)
    }

    private static let promptFallback = """
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
}
