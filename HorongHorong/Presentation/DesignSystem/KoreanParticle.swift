import Foundation

/// 앞 글자의 받침을 보고 **한국어 조사를 골라 붙인다.**
///
/// 화면 문구를 값으로 조립하면 «할일가 1개뿐» 같은 말이 나온다. 한국어는 조사가 앞말의
/// 받침에 따라 달라지는데, 문자열 보간은 그걸 모른다.
///
/// 실제로 AI 실험실에서 이 문제가 났다 — 태스크에 따라 «할일»(주간)과 «주간 목표»(월간) 를
/// 바꿔 끼우는데, 한쪽은 받침이 있고 한쪽은 없다.
///
/// ```swift
/// "할일".withParticle(.subject)      // "할일이"
/// "주간 목표".withParticle(.subject)  // "주간 목표가"
/// ```
enum KoreanParticle {
    /// 이/가
    case subject
    /// 을/를
    case object
    /// 은/는
    case topic
    /// 과/와
    case and
    /// 으로/로
    case direction

    /// (받침 있을 때, 없을 때)
    fileprivate var forms: (withFinal: String, withoutFinal: String) {
        switch self {
        case .subject:   return ("이", "가")
        case .object:    return ("을", "를")
        case .topic:     return ("은", "는")
        case .and:       return ("과", "와")
        // `으로/로` 는 예외가 하나 있다 — ㄹ 받침은 받침이 없는 것처럼 «로» 를 쓴다.
        case .direction: return ("으로", "로")
        }
    }
}

extension String {
    /// 이 말에 어울리는 조사를 붙여 돌려준다. 한글이 아니면 **받침 없는 쪽**으로 붙인다 —
    /// 영문·숫자로 끝나는 말에 «이/을/은» 을 붙이면 더 어색하다.
    func withParticle(_ particle: KoreanParticle) -> String {
        self + particleSuffix(particle)
    }

    /// 붙일 조사만.
    func particleSuffix(_ particle: KoreanParticle) -> String {
        let forms = particle.forms
        guard let scalar = unicodeScalars.last?.value else { return forms.withoutFinal }
        // 한글 음절 영역(가~힣). 밖이면 받침 없는 쪽으로 본다.
        guard (0xAC00...0xD7A3).contains(scalar) else { return forms.withoutFinal }
        // 음절 = ((초성 × 21) + 중성) × 28 + 종성. 나머지가 0 이면 받침이 없다.
        let finalIndex = (scalar - 0xAC00) % 28
        if finalIndex == 0 { return forms.withoutFinal }
        // ㄹ(종성 8번) 받침은 «으로» 가 아니라 «로» 를 쓴다. 다른 조사에는 이 예외가 없다.
        if particle == .direction, finalIndex == 8 { return forms.withoutFinal }
        return forms.withFinal
    }
}
