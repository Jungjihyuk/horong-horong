import Foundation

/// 모델이 낸 목표 후보 하나. 주간·월간이 같은 모양을 쓴다.
///
/// **초안(draft)** 인 이유는 사용자가 화면에서 고쳐 쓰는 값이기 때문이다. 그대로 저장되지 않는다.
/// 앱이 어떤 목표 타입인지(`cadence`)와 어느 공급자에서 왔는지(`source`)를 붙여 자기 도메인 값으로 바꾼다.
public struct GoalSuggestionDraft: Sendable, Hashable {
    public let title: String
    public let reason: String
    public let memoIDs: [UUID]
    public let childGoalIDs: [UUID]
    public let scheduleText: String
    public let criterion: String
    public let targetValueText: String
    public let emoji: String

    public init(
        title: String,
        reason: String,
        memoIDs: [UUID],
        childGoalIDs: [UUID] = [],
        scheduleText: String,
        criterion: String,
        targetValueText: String,
        emoji: String
    ) {
        self.title = title
        self.reason = reason
        self.memoIDs = memoIDs
        self.childGoalIDs = childGoalIDs
        self.scheduleText = scheduleText
        self.criterion = criterion
        self.targetValueText = targetValueText
        self.emoji = emoji
    }
}

/// 모델 응답의 JSON 모양. 주간은 `memoIDs` 또는 `items`, 월간은 `goalIDs` 를 채워 보낸다.
struct GoalSuggestionPayload: Codable {
    let suggestions: [Item]

    enum IDValue: Codable, Sendable {
        case int(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                self = .int(intVal)
            } else if let strVal = try? container.decode(String.self) {
                let trimmed = strVal.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intVal = Int(trimmed) {
                    self = .int(intVal)
                } else {
                    self = .string(trimmed)
                }
            } else {
                throw DecodingError.typeMismatch(
                    IDValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let i): try container.encode(i)
            case .string(let s): try container.encode(s)
            }
        }
    }

    /// id 목록. 원소가 **배열로 한 겹 더 감싸여 와도** 펴서 받는다.
    ///
    /// 실측(2026-08-19/20) — `gemma-4-e4b` 계열이 `[[16],[17],[18]]` 처럼 냈다. mlx·ollama
    /// 양쪽에서 5건이 나왔고, 묶음 내용은 멀쩡했는데 껍데기 한 겹 때문에 통째로 버려졌다.
    ///
    /// **한 겹만 편다.** 두 겹 이상은 모델이 다른 뜻으로 쓴 것일 수 있어 함부로 짐작하지 않는다.
    /// `items` 는 계약상 평평한 id 목록이므로 한 겹까지는 잡음이 분명하다.
    struct IDList: Codable, Sendable {
        let values: [IDValue]

        init(from decoder: Decoder) throws {
            // 원소마다 **자기 decoder** 를 받으므로, 스칼라 시도가 실패해도
            // 바깥 배열의 읽기 위치가 흐트러지지 않는다.
            let elements = try [Element](from: decoder)
            self.values = elements.flatMap { element in
                switch element {
                case .single(let value): return [value]
                case .nested(let values): return values
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            try values.encode(to: encoder)
        }

        private enum Element: Codable {
            case single(IDValue)
            case nested([IDValue])

            init(from decoder: Decoder) throws {
                if let one = try? IDValue(from: decoder) {
                    self = .single(one)
                } else {
                    self = .nested(try [IDValue](from: decoder))
                }
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .single(let value): try value.encode(to: encoder)
                case .nested(let values): try values.encode(to: encoder)
                }
            }
        }
    }

    struct Item: Codable {
        let title: String
        let reason: String
        let memoIDs: IDList?
        let goalIDs: IDList?
        let items: IDList?
        let scheduleText: String?
        let criterion: String?
        let emoji: String?

        enum CodingKeys: String, CodingKey {
            case title
            case reason
            case memoIDs
            case goalIDs
            case items
            case scheduleText
            case criterion
            case emoji
        }
    }

    /// 읽지 못한 이유. **"못 읽었다"만 남기면 원인을 영영 모른다.**
    ///
    /// 실측에서 세 공급자가 동시에 `decodeFailed` 였는데, 이유가 안 남아
    /// 프롬프트 문제인지 모델 문제인지 파서 문제인지 가릴 수 없었다.
    ///
    /// 키 이름은 **우리 스키마**라 사용자 내용이 아니다 — 그대로 남겨도 된다.
    enum DecodeFailure: Error {
        /// `{` 를 아예 못 찾았다. 모델이 산문만 냈다는 뜻이다 — 프롬프트가 안 먹은 것이다.
        case noJSONObject
        /// `{` 는 있는데 `}` 가 없다. **응답이 중간에 잘렸다** — 토큰 상한을 의심할 자리다.
        case truncated
        /// 괄호는 둘 다 있는데 JSON 문법이 깨졌다.
        case malformed
        /// 문법은 맞는데 **필수 키가 없다.** `scheduleText`·`criterion` 처럼 하나만 빠져도
        /// 제안 전체가 버려진다 — id 는 다섯 갈래로 방어하면서 스키마는 전부 아니면 전무다.
        case missingKey(String)
        /// 키는 있는데 타입이 다르다(문자열 자리에 숫자 등).
        case typeMismatch(String)

        /// 로그·기록에 실을 짧은 이름.
        public var reason: String {
            switch self {
            case .noJSONObject: return "noJSON"
            case .truncated: return "truncated"
            case .malformed: return "malformed"
            case .missingKey(let key): return "missingKey:\(key)"
            case .typeMismatch(let key): return "typeMismatch:\(key)"
            }
        }
    }

    /// 모델이 JSON 앞뒤에 설명을 붙여도 살려낸다 — 첫 `{` 부터 마지막 `}` 까지만 잘라 읽는다.
    static func decode(from responseText: String) -> Result<GoalSuggestionPayload, DecodeFailure> {
        let jsonText = extractJSONObject(from: responseText)
        
        guard jsonText.firstIndex(of: "{") != nil else {
            return .failure(.noJSONObject)
        }
        guard jsonText.lastIndex(of: "}") != nil else {
            return .failure(.truncated)
        }
        guard let data = jsonText.data(using: .utf8) else {
            return .failure(.malformed)
        }

        do {
            return .success(try JSONDecoder().decode(GoalSuggestionPayload.self, from: data))
        } catch let DecodingError.keyNotFound(key, _) {
            return .failure(.missingKey(key.stringValue))
        } catch let DecodingError.typeMismatch(_, context) {
            return .failure(.typeMismatch(context.codingPath.last?.stringValue ?? "?"))
        } catch let DecodingError.valueNotFound(_, context) {
            return .failure(.missingKey(context.codingPath.last?.stringValue ?? "?"))
        } catch {
            return .failure(.malformed)
        }
    }

    static func extractJSONObject(from text: String) -> String {
        var processedText = text
        
        // 1. <think> 블록 제거
        if let thinkStart = processedText.range(of: "<think>"),
           let thinkEnd = processedText.range(of: "</think>") {
            processedText.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
        }
        
        // 2. 마크다운 코드 블록(```json ... ```) 추출 시도
        if let codeBlockStart = processedText.range(of: "```json"),
           let codeBlockEnd = processedText.range(of: "```", range: codeBlockStart.upperBound..<processedText.endIndex) {
            processedText = String(processedText[codeBlockStart.upperBound..<codeBlockEnd.lowerBound])
        } else if let codeBlockStart = processedText.range(of: "```"),
                  let codeBlockEnd = processedText.range(of: "```", range: codeBlockStart.upperBound..<processedText.endIndex) {
            processedText = String(processedText[codeBlockStart.upperBound..<codeBlockEnd.lowerBound])
        }
        
        // 3. 첫 번째 '{' 와 마지막 '}' 사이 추출
        guard let start = processedText.firstIndex(of: "{"),
              let end = processedText.lastIndex(of: "}") else {
            return processedText
        }
        return String(processedText[start...end])
    }
}
