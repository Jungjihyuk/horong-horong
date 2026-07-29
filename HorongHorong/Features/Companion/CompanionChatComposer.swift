import Foundation

/// 사용자의 말이 오늘 할일·일정에 관한 것인지 판정한다.
///
/// 모델이 도구를 부를지 스스로 정하게 두면 호출률이 들쭉날쭉하므로,
/// 여기서 코드로 판정해 필요할 때만 할일 목록을 프롬프트에 끼워 넣는다.
enum CompanionTaskQuestion {
    private static let keywords = [
        "할일", "할 일", "일정", "스케줄", "계획", "태스크", "todo", "to-do",
        "뭐 해야", "뭐해야", "뭐부터", "무엇을 해야", "남은 거", "남은거",
    ]

    static func matches(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return keywords.contains { normalized.contains($0) }
    }
}

/// 모델에게 실제로 보낼 입력을 만든다.
/// 화면에 보이는 사용자 메시지는 그대로 두고, 모델 입력에만 참고 정보를 덧붙인다.
enum CompanionChatComposer {
    static func modelInput(userMessage: String, taskDigest: String?) -> String {
        guard let taskDigest, !taskDigest.isEmpty else { return userMessage }
        // 목록은 화면에 타임라인으로 따로 그리므로, 모델에게는 나열하지 말라고 못 박는다.
        return """
        \(taskDigest)

        사용자: \(userMessage)

        (목록은 화면에 이미 표시된다. 항목을 나열하지 말고 한 문장으로만 코멘트해.)
        """
    }
}

/// 모델 응답 다듬기.
///
/// 프롬프트로 "목록·굵은 글씨 쓰지 마"라고 해도 작은 모델은 자주 어긴다.
/// 지시로 싸우는 대신 결과에서 마크다운 기호만 걷어낸다.
enum CompanionReplyFormatter {
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")

        let lines = result
            .components(separatedBy: .newlines)
            .map { stripBullet($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        // 줄바꿈은 살린다. 공백으로 이어 붙이면 시각·항목이 뭉개져 읽을 수 없다.
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 줄 앞의 `- `, `* `, `1. ` 같은 목록 기호를 뗀다.
    private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        // "1. " / "12. " 형태
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") {
                return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }
}
