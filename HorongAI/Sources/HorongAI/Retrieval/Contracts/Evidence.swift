import Foundation

/// 답의 근거가 되는 조각 하나.
///
/// 지금 근거는 조립된 **문자열 하나**로 흘러다녀서, 여러 조각이 합쳐지고 나면
/// 어느 검색기가 무엇을 얼마나 잘 찾았는지 되짚을 수 없다. 그래서 recall@k 같은
/// 검색 품질 채점이 아예 불가능하다 — 최종 답의 좋고 나쁨만 볼 수 있을 뿐이다.
///
/// 조각마다 **어디서 왔고(`source`) 무엇이며(`id`) 얼마나 잘 맞았는지(`score`)** 를 달고 다니면,
/// 답이 나빴을 때 "검색이 못 찾은 것"과 "모델이 근거를 못 쓴 것"을 나눌 수 있다.
public struct Evidence: Sendable, Equatable, Identifiable {
    /// 이 조각의 안정된 식별자. 채점할 때 "정답 조각을 가져왔나"를 이 값으로 맞춰 본다.
    /// 실행마다 달라지면 안 되므로 UUID 가 아니라 내용에서 나온 이름을 쓴다.
    public let id: String
    /// 어느 검색기에서 왔나 (`"appFacts"` · `"settingsIndex"` · `"guide"`).
    ///
    /// 열거형이 아닌 이유는 근거 출처가 앱마다·기능마다 늘기 때문이다.
    /// 새 출처가 생길 때 패키지를 고쳐야 한다면 계약이 잘못된 것이다.
    public let source: String
    /// 프롬프트에 실릴 문장.
    public let text: String
    /// 검색기가 매긴 점수. **없는 검색기도 있다** — 키워드가 걸렸는지만 보는 곳은 순위를 매기지 않는다.
    /// 척도가 검색기마다 다르므로 서로 다른 출처의 점수를 그대로 비교하면 안 된다(융합은 RRF 몫).
    public let score: Double?

    public init(id: String, source: String, text: String, score: Double? = nil) {
        self.id = id
        self.source = source
        self.text = text
        self.score = score
    }
}
