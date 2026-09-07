import Foundation
import Observation

@MainActor
@Observable
final class QuickLinkViewModel {
    var urlText = ""
    var titleText = ""
    private(set) var errorMessage: String?

    private let repository: ReferenceRepository
    private let clipboard: ClipboardGateway

    init(repository: ReferenceRepository, clipboard: ClipboardGateway) {
        self.repository = repository
        self.clipboard = clipboard
    }

    var normalizedURL: String? { ReferenceURLPolicy.normalize(urlText) }
    var canSave: Bool { normalizedURL != nil }

    func loadClipboard() {
        guard let text = clipboard.readText(), let normalized = ReferenceURLPolicy.normalize(text) else { return }
        urlText = normalized
    }

    func save() -> Bool {
        guard let url = normalizedURL else {
            errorMessage = "올바른 웹 주소를 입력해 주세요."
            return false
        }
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? ReferenceURLPolicy.fallbackTitle(for: url) : trimmedTitle
        do {
            try repository.addLink(title: title, url: url)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "링크를 저장하지 못했어요."
            return false
        }
    }
}
