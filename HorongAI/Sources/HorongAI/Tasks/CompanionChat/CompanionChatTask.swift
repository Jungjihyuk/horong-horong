import Foundation

/// 캐릭터와의 대화 태스크. 모델에게 실제로 보낼 입력을 만든다.
///
/// 화면에 보이는 사용자 메시지는 그대로 두고, **모델 입력에만** 참고 정보를 덧붙인다.
public enum CompanionChatTask {

    /// - Parameters:
    ///   - taskDigest: 할일 질문일 때의 오늘 목록. 있으면 근거보다 우선한다.
    ///   - evidence: 근거 조각. 순서가 곧 프롬프트에 실리는 순서다(리랭킹은 넘기기 전에 끝나 있어야 한다).
    public static func modelInput(
        userMessage: String,
        taskDigest: String? = nil,
        evidence: [Evidence] = []
    ) -> String {
        if let taskDigest, !taskDigest.isEmpty {
            // 목록은 화면에 타임라인으로 따로 그리므로, 모델에게는 나열하지 말라고 못 박는다.
            return """
            \(taskDigest)

            사용자: \(userMessage)

            (목록은 화면에 이미 표시된다. 항목을 나열하지 말고 한 문장으로만 코멘트해.)
            """
        }

        let texts = evidence.map(\.text).filter { !$0.isEmpty }
        guard !texts.isEmpty else { return userMessage }

        // 근거 밖의 이야기를 지어내지 않도록, 넣어준 내용만 쓰라고 못 박는다.
        return """
        [호롱호롱 사용법 — 아래 내용만 사실이다]
        \(texts.joined(separator: separator))

        사용자: \(userMessage)

        (위에 없는 기능이나 이름은 절대 말하지 마. 모르면 모른다고 답해.
        무엇이 있는지 물으면 목록을 그대로 알려줘.
        어떻게 바꾸는지 물으면 "바꾸는 곳" 경로를 그대로 한 줄로 알려줘. 길게 풀어 쓰지 마.)
        """
    }

    /// 조각 사이는 빈 줄로 띄운다.
    ///
    /// 옮기기 전에는 이음새가 두 종류였다 — 앱 사실끼리는 `\n`, 설명서와는 `\n\n`.
    /// 앱이 근거를 미리 조립해 두 덩어리로 넘겼기 때문에 생긴 구분이지 의도한 규칙이 아니었다.
    /// 조각 목록을 그대로 받는 지금은 균일하게 띄운다.
    ///
    /// **빈 줄은 경계를 약하게 암시할 뿐 출처를 말해주지 않는다.** 신뢰도가 다른 근거
    /// (코드에서 뽑은 확정 사실 vs 색인이 추측한 설정 위치)를 모델이 구분하려면
    /// `[설명서]` 같은 라벨이 필요하다. 그건 프롬프트 설계 변경이고 토큰도 먹으므로
    /// **컴패니언 평가 세트를 만든 뒤** 재보고 정한다 — 지금 바꾸면 좋아졌는지 알 수단이 없다.
    private static let separator = "\n\n"
}
