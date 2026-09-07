import AppKit

@MainActor
final class PasteboardClipboardAdapter: ClipboardGateway {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}
