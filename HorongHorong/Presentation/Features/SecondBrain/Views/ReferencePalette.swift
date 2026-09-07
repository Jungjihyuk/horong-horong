import SwiftUI

extension ReferenceNoteColor {
    var paper: Color { ReferencePalette.color(fromHex: paperHex) }
    /// 접힌 모서리. 종이보다 한 톤 어둡다.
    var edge: Color { ReferencePalette.color(fromHex: edgeHex) }
    /// 글씨. 종이색 계열이라 인쇄물이 아니라 «적어 둔 쪽지» 로 읽힌다.
    var ink: Color { ReferencePalette.color(fromHex: inkHex) }
}

enum ReferencePalette {
    /// 도메인 배지 색. 사이트마다 다른 색이 붙어 목록에서 눈으로 구분된다.
    private static let badgeTints: [Color] = [
        Color(red: 0.91, green: 0.54, blue: 0.36),
        Color(red: 0.85, green: 0.64, blue: 0.25),
        Color(red: 0.44, green: 0.68, blue: 0.39),
        Color(red: 0.48, green: 0.61, blue: 0.78),
        Color(red: 0.62, green: 0.56, blue: 0.75),
        Color(red: 0.76, green: 0.53, blue: 0.62),
    ]

    /// 같은 도메인은 늘 같은 색을 받는다. 무작위로 고르면 다시 그릴 때마다 색이 바뀐다.
    static func badgeTint(for seed: String) -> Color {
        guard !seed.isEmpty else { return badgeTints[0] }
        var hash = 0
        for scalar in seed.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) % 997
        }
        return badgeTints[abs(hash) % badgeTints.count]
    }

    /// 배지에 넣을 한 글자.
    static func badgeLetter(for seed: String) -> String {
        let cleaned = seed.drop { !$0.isLetter && !$0.isNumber }
        guard let first = cleaned.first else { return "?" }
        return String(first).uppercased()
    }

    static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return .gray }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

/// 포스트잇의 좌하단 접힌 모서리.
///
/// 종이 느낌을 만드는 것은 색이 아니라 이 삼각형이다 — 모서리 하나만 각지게 두고
/// 그 자리에 45° 그라데이션을 얹으면 «접힌 종이» 로 읽힌다.
struct StickyNoteShape: View {
    let color: ReferenceNoteColor
    var cornerSize: CGFloat = 16
    var radius: CGFloat = 3

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
            .fill(color.paper)

            Path { path in
                path.move(to: CGPoint(x: 0, y: cornerSize))
                path.addLine(to: CGPoint(x: cornerSize, y: cornerSize))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.closeSubpath()
            }
            .fill(color.edge)
            .frame(width: cornerSize, height: cornerSize)
        }
    }
}
