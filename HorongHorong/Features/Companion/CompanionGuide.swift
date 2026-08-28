import Foundation
import HorongAI

/// 설명서 마크다운을 앱 번들에서 읽어 온다.
///
/// 자르고 고르는 일은 `GuideRetriever`(패키지)가 한다. 여기 남은 것은 **앱 번들을 아는 부분**뿐이다 —
/// 패키지가 `USER_GUIDE.md` 를 알면 평가가 앱 빌드에 묶인다.
enum CompanionGuide {
    static let resourceName = "USER_GUIDE"

    static func loadFromBundle(_ bundle: Bundle = .main) -> [GuideSection] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return GuideRetriever.sections(from: markdown)
    }
}

/// 사용자의 말이 "이 앱을 어떻게 쓰는지" 묻는 것인지 판정한다.
enum CompanionGuideQuestion {
    private static let keywords = [
        "어떻게", "어디서", "어디에", "어디야", "방법", "하는 법", "하는법",
        "뭐가 있", "뭐 있", "무엇이 있", "설정", "바꾸", "켜", "끄", "쓰는",
        "사용법", "기능", "가능해", "돼?", "되나", "할 수 있",
    ]

    static func matches(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return keywords.contains { normalized.contains($0) }
    }
}
