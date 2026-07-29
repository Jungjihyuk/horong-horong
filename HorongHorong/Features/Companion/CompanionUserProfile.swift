import Foundation

/// 컴패니언이 알아둘 사용자 정보.
///
/// 앱이 이미 아는 것(할일·집중 기록·카테고리)은 여기에 두지 않는다.
/// 앱이 알 수 없는 것 — 어떻게 불러주길 바라는지, 무엇을 감안해줬으면 하는지 — 만 담는다.
struct CompanionUserProfile: Equatable, Sendable {
    var nickname: String
    var note: String

    static let empty = CompanionUserProfile(nickname: "", note: "")

    var isEmpty: Bool { nickname.isEmpty && note.isEmpty }

    /// 저장 전 정리. 길이를 제한해 짧은 컨텍스트를 지킨다.
    static func normalized(nickname: String, note: String) -> CompanionUserProfile {
        CompanionUserProfile(
            nickname: clip(nickname, to: Constants.companionUserNicknameMaxLength),
            note: clip(note, to: Constants.companionUserNoteMaxLength)
        )
    }

    private static func clip(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 시스템 프롬프트에 덧붙일 문단. 비어 있으면 아무것도 더하지 않는다.
    var promptSection: String {
        // 지시문의 말투를 모델이 그대로 따라하므로, 이 문단도 존댓말로 맞춘다.
        var lines: [String] = []
        if !nickname.isEmpty {
            lines.append("사용자를 \"\(nickname)\" 이라고 부릅니다.")
        }
        if !note.isEmpty {
            lines.append("사용자가 알아줬으면 하는 것: \(note)")
        }
        guard !lines.isEmpty else { return "" }
        return "\n\n사용자에 대해 알아둘 것:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }

    static func load(from defaults: UserDefaults = .standard) -> CompanionUserProfile {
        normalized(
            nickname: defaults.string(forKey: Constants.AppStorageKey.companionUserNickname) ?? "",
            note: defaults.string(forKey: Constants.AppStorageKey.companionUserNote) ?? ""
        )
    }
}
