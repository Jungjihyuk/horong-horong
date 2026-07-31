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
        // 문구가 중요하다. `사용자를 "이름" 이라고 부릅니다` 처럼 호칭을 따옴표로 지시하면
        // 안전 필터가 역할 조작으로 오탐해 응답 자체를 막아버린다(실측 12/12 차단).
        // 사실을 나열하는 `키: 값` 형태는 통과한다.
        var lines: [String] = []
        if !nickname.isEmpty {
            lines.append("사용자 호칭: \(nickname)")
        }
        if !note.isEmpty {
            lines.append("참고 사항: \(note)")
        }
        guard !lines.isEmpty else { return "" }
        return "\n\n" + lines.joined(separator: "\n")
    }

    static func load(from defaults: UserDefaults = .standard) -> CompanionUserProfile {
        normalized(
            nickname: defaults.string(forKey: Constants.AppStorageKey.companionUserNickname) ?? "",
            note: defaults.string(forKey: Constants.AppStorageKey.companionUserNote) ?? ""
        )
    }
}
