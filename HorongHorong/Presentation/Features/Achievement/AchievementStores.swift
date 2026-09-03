import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 여정 화면이 쓰는 설정 저장소들.
 
  이미지·깃발·비전 순서를 `UserDefaults` 와 파일에 둔다. 화면 상태가 아니라
  **앱을 껐다 켜도 남아야 하는 것**이라 따로 뺐다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementJourneyImageStore {
    private static let defaultsKey = "achievementJourneyImagePaths"

    static func imageURL(for roleID: String) -> URL? {
        guard let path = imagePaths()[roleID] else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func saveImage(from sourceURL: URL, for roleID: String) throws -> URL {
        let directory = try imageDirectory()
        var paths = imagePaths()
        if let previousPath = paths[roleID] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: previousPath))
        }

        let destination = directory
            .appendingPathComponent(sanitized(roleID), isDirectory: false)
            .appendingPathExtension("jpg")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if let image = NSImage(contentsOf: sourceURL),
           let data = jpegData(for: image, maxPixelLength: 1200) {
            try data.write(to: destination, options: .atomic)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }

        paths[roleID] = destination.path
        UserDefaults.standard.set(paths, forKey: defaultsKey)
        return destination
    }

    static func removeImage(for roleID: String) {
        var paths = imagePaths()
        if let path = paths[roleID] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        paths.removeValue(forKey: roleID)
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private static func imagePaths() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func imageDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("HorongHorong/JourneyImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? UUID().uuidString : result
    }

    private static func jpegData(for image: NSImage, maxPixelLength: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixelLength / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else { return nil }
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }
}

enum AchievementJourneyFlagStore {
    private static var defaultsKey: String { Constants.AppStorageKey.achievementJourneyFlagSelections }
    private static let emptySlot = "-"

    static func goalIDs(for key: String, maxCount: Int) -> [UUID?] {
        guard let value = flagSelections()[key] else { return [] }
        return Array(value
            .split(separator: ",", omittingEmptySubsequences: false)
            .prefix(maxCount)
            .map { item -> UUID? in
                let text = String(item)
                return text == emptySlot ? nil : UUID(uuidString: text)
            })
    }

    static func setGoalID(_ goalID: UUID?, at index: Int, for key: String, maxCount: Int) {
        guard index >= 0, index < maxCount else { return }
        var ids = goalIDs(for: key, maxCount: maxCount)
        while ids.count < maxCount {
            ids.append(nil)
        }

        if let goalID {
            // 같은 월간 목표는 하나의 깃발에만 지정한다.
            for (offset, existing) in ids.enumerated() where existing == goalID {
                ids[offset] = nil
            }
        }
        ids[index] = goalID

        let encoded = ids
            .prefix(maxCount)
            .map { $0?.uuidString ?? emptySlot }
            .joined(separator: ",")
        var selections = flagSelections()
        selections[key] = encoded
        UserDefaults.standard.set(selections, forKey: defaultsKey)
    }

    private static func flagSelections() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

enum AchievementVisionOrderStore {
    private static var defaultsKey: String { Constants.AppStorageKey.achievementVisionOrder }

    /// 역할별로 사용자가 지정한 비전 순서(UUID 목록)를 돌려준다.
    static func order(for roleID: String) -> [UUID] {
        guard let value = orders()[roleID] else { return [] }
        return value
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    static func setOrder(_ ids: [UUID], for roleID: String) {
        var orders = orders()
        orders[roleID] = ids.map(\.uuidString).joined(separator: ",")
        UserDefaults.standard.set(orders, forKey: defaultsKey)
    }

    private static func orders() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

// 평가 하네스(HorongHorongTests)에서 @testable 로 접근하기 위해 internal 유지
