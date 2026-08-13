import Foundation

/// `.md` 템플릿을 읽어 `{{key}}` 자리를 값으로 바꾼다.
///
/// 규약은 앱이 쓰던 것을 그대로 옮겼다 — 파일을 못 읽으면 코드에 박아둔 폴백을 쓴다.
/// 번들만 `Bundle.main`(앱)에서 `Bundle.module`(패키지)로 바뀌었다.
///
/// 폴백이 조용히 쓰이면 프롬프트가 통째로 달라지므로, 리소스 배선이 끊기면
/// 스냅샷 테스트(`PromptSnapshotTests`)가 바이트 단위로 잡아낸다.
public enum PromptRenderer {

    public static func render(
        fileName: String,
        fallback: String,
        values: [String: String]
    ) -> String {
        var result = load(fileName: fileName) ?? fallback
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    private static func load(fileName: String) -> String? {
        guard let url = Bundle.module.url(forResource: fileName, withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
