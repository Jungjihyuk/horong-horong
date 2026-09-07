import Foundation

enum DiaryQuickCapturePolicy {
    static func appending(_ raw: String, at now: Date, to body: String, calendar: Calendar = .current) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let stamp = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let line = "• \(stamp) \(text)"
        guard !body.isEmpty else { return line }
        return body + (body.hasSuffix("\n") ? "" : "\n") + line
    }

    static func slot(at date: Date, calendar: Calendar = .current) -> DiaryMoodSlot {
        calendar.component(.hour, from: date) < 12 ? .morning : .afternoon
    }
}
