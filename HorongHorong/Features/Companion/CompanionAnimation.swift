import AppKit

/// 컴패니언 스프라이트 시퀀스. rawValue 가 곧 리소스 하위 폴더 이름이다.
enum CompanionAnimation: String, CaseIterable, Sendable {
    case idle
    case waiting
    case jumping
    case waving
    case review
    case running
    case runningLeft = "running-left"
    case runningRight = "running-right"
    case failed

    var directoryName: String { rawValue }

    /// 프레임 한 장을 보여줄 시간(초).
    var frameDuration: Double {
        switch self {
        case .idle, .waiting:
            return 0.28
        case .review, .failed:
            return 0.22
        case .waving, .jumping:
            return 0.16
        case .running, .runningLeft, .runningRight:
            return 0.12
        }
    }

    /// false 면 마지막 프레임에서 멈춘다(1회 재생).
    var loops: Bool {
        switch self {
        case .waving, .jumping:
            return false
        default:
            return true
        }
    }
}

/// 번들에 폴더 참조로 들어있는 PNG 시퀀스를 읽어 캐시한다.
/// 프레임은 `00.png` 부터 번호가 끊길 때까지 이어 붙인다.
@MainActor
final class CompanionSpriteLoader {
    static let shared = CompanionSpriteLoader()

    private var cache: [String: [NSImage]] = [:]
    private var maskCache: [String: CompanionSpriteMask] = [:]

    private init() {}

    func frames(for character: CompanionCharacter, animation: CompanionAnimation) -> [NSImage] {
        let key = "\(character.spriteRoot)/\(animation.directoryName)"
        if let cached = cache[key] { return cached }
        let frames = loadFrames(at: key)
        cache[key] = frames
        return frames
    }

    /// 실제로 그려진 부분만 나타내는 격자 마스크. 클릭·호버 판정에 쓰며 한 번 계산해 캐시한다.
    func hitMask(for character: CompanionCharacter, animation: CompanionAnimation) -> CompanionSpriteMask {
        let key = "\(character.spriteRoot)/\(animation.directoryName)"
        if let cached = maskCache[key] { return cached }

        let masks = frames(for: character, animation: animation).compactMap(Self.mask(of:))
        let mask = CompanionSpriteMetrics.union(masks)
        maskCache[key] = mask
        return mask
    }

    private static func mask(of image: NSImage) -> CompanionSpriteMask? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.bitmapData,
              rep.hasAlpha,
              rep.bitsPerSample == 8,
              rep.samplesPerPixel >= 4 else {
            return nil
        }

        let samplesPerPixel = rep.samplesPerPixel
        let bytesPerRow = rep.bytesPerRow
        // 알파 10% 미만은 사실상 안 보이므로 클릭 영역에서 뺀다.
        let threshold: UInt8 = 25

        return CompanionSpriteMetrics.mask(
            width: rep.pixelsWide,
            height: rep.pixelsHigh
        ) { x, y in
            data[y * bytesPerRow + x * samplesPerPixel + 3] > threshold
        }
    }

    private func loadFrames(at relativePath: String) -> [NSImage] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let directory = resourceURL.appendingPathComponent(relativePath, isDirectory: true)
        var images: [NSImage] = []
        var index = 0
        while true {
            let url = directory.appendingPathComponent(String(format: "%02d.png", index))
            guard let image = NSImage(contentsOf: url) else { break }
            images.append(image)
            index += 1
        }
        return images
    }
}
