import Foundation

enum TestRepository {
    static func root(from filePath: String = #filePath) -> URL? {
        var url = URL(fileURLWithPath: filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Evals").path) {
                return url
            }
        }
        return nil
    }

    static func goldenDirectory(from filePath: String = #filePath) -> URL? {
        root(from: filePath)?.appendingPathComponent("Evals/golden", isDirectory: true)
    }
}
