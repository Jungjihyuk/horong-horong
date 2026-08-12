import Foundation

public typealias SuiteID = String

/// 평가 케이스 1개를 표현하는 뼈대 모델
public struct EvalCase {
    public let id: String
    public let suite: SuiteID
    public let input: Any
    public let expected: Any?
    
    public init(id: String, suite: SuiteID, input: Any, expected: Any? = nil) {
        self.id = id
        self.suite = suite
        self.input = input
        self.expected = expected
    }
}

/// 채점 대상이 되는 AI의 출력물
public protocol SkillOutput {
    // 마커 프로토콜. 각 태스크마다 구체적인 출력 구조체를 정의하여 사용
}

/// AI 기능의 평가를 담당하는 채점자 뼈대 프로토콜
public protocol EvalScorer {
    /// 이 채점자가 담당하는 테스트 스위트의 식별자
    var suite: SuiteID { get }
    
    /// 결정적 평가를 수행하여 지표별 점수 딕셔너리를 반환한다.
    func score(case: EvalCase, output: SkillOutput) -> [String: Double]
}
