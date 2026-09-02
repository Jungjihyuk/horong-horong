import Foundation

/// vault(옵시디언 폴더)를 읽는다. 구현은 `Data/Repositories/` 에 있다.
///
/// **읽기 전용이다.** 원본은 옵시디언이 관리하고 이 앱은 보여주기만 한다 —
/// 쓰기를 넣는 순간 두 프로그램이 같은 파일을 두고 다투게 된다.
@MainActor
protocol VaultRepository {
    /// 폴더를 훑어 트리와 위키 링크 색인을 만든다.
    ///
    /// `forceReload` 가 `false` 면 캐시를 쓴다. 탭을 오갈 때마다 디스크를 다시 훑지
    /// 않기 위해서다 — vault 가 앱 밖에서 바뀌면 새로고침으로 반영한다.
    func scan(kind: VaultKind, vault: URL, forceReload: Bool) async -> VaultScan

    /// 문서 본문. 읽지 못하면 `nil`.
    func document(at url: URL) async -> String?

    /// `[[제목]]` 이 가리키는 문서를 찾는다. 같은 이름이 여럿이면 현재 문서에 가까운 쪽.
    func resolveWikiLink(_ title: String, from current: URL?, in index: [String: [URL]]) -> URL?
}
