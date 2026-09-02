import Foundation

// vault(옵시디언 폴더)를 화면에 보여주기 위한 값 타입들.
//
// **Domain 에 있는 이유**: `VaultRepository` 계약에 등장한다. 파일 시스템을 실제로 훑는
// 일은 `Data/DataSources/Local/VaultCatalog` 가 한다.

enum VaultKind: Sendable {
    case knowledge
    case works

    var title: String {
        switch self {
        case .knowledge: return "Knowledge"
        case .works: return "Works"
        }
    }
}

struct VaultRoot: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let title: String
    let url: URL
    /// vault 루트 기준 상대 경로. 이 폴더와 그 하위는 트리에서 뺀다.
    let excludedRelativePaths: [String]
}

struct VaultNode: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [VaultNode]

    var listChildren: [VaultNode]? {
        isDirectory ? children : nil
    }
}

/// 한 번의 순회가 내놓는 결과. 트리와 위키링크 지도를 **함께** 만든다.
///
/// 예전에는 `tree(for:)` 와 `indexMarkdown(in:)` 이 같은 디렉터리를 각각 훑었다.
/// 목적은 다르지만 방문 대상이 같아서 순회를 두 번 한 셈이었다
/// (실측 Knowledge 108ms → 합쳐서 33ms).
struct VaultScan: Sendable {
    let roots: [VaultNode]
    /// 파일명(확장자 제외) → 후보 경로들.
    ///
    /// **배열인 이유**: 같은 이름의 노트가 여러 폴더에 있을 수 있다. 예전에는
    /// `[String: URL]` 이라 나중에 만난 것이 앞의 것을 조용히 덮어썼고, 위키링크가
    /// 엉뚱한 파일로 갔다 (실측 2026-09-01: Knowledge 의 md 1,369개 중 34개가 이름 충돌).
    let wikiIndex: [String: [URL]]

    static let empty = VaultScan(roots: [], wikiIndex: [:])
}
