import Foundation

/// Agent 작업 폴더의 뿌리 경로를 정한다.
///
/// 예전 버전은 아이디어 폴더와 출력 폴더를 따로 저장했다. 그 둘에서 뿌리 하나를 되살리는
/// 규칙이라, **한 번 정해지면 다시 안 도는 이관 로직**이다. 뷰 안에 두면 검사할 수 없어 뺐다.
enum AgentRootPath {
    /// - Parameters:
    ///   - stored: 지금 저장된 값. **한 번도 정한 적 없으면 `nil`.**
    ///     빈 문자열과 구분해야 한다 — 옛 설정을 되살릴지 말지가 여기서 갈린다.
    ///   - fallback: 되살릴 것이 없을 때 쓸 기본 경로.
    static func resolve(
        stored: String?,
        legacyIdeaDirectory: String,
        legacyOutputDirectory: String,
        fallback: String
    ) -> String {
        if stored == nil, let migrated = migrated(idea: legacyIdeaDirectory, output: legacyOutputDirectory) {
            return migrated
        }
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// 아이디어·출력이 같은 폴더였으면 그것이 뿌리다. 다르면 출력 쪽을 택한다 —
    /// 계획 파일이 거기 쌓여 있어 잃으면 곤란한 쪽이다.
    private static func migrated(idea: String, output: String) -> String? {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !idea.isEmpty, idea == output { return idea }
        if !output.isEmpty { return output }
        if !idea.isEmpty { return idea }
        return nil
    }
}
