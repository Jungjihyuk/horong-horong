import CoreGraphics
import Foundation

/// 스프라이트에서 실제로 그려진 부분만 나타내는 격자 마스크.
///
/// 스프라이트 PNG 는 캐릭터 주위·사이사이가 투명하다. 이미지 프레임 전체를 클릭 영역으로 쓰면
/// 눈에 보이지 않는 빈 공간까지 아래 앱의 클릭을 가로챈다. 실루엣을 격자로 근사해
/// 그려진 칸만 클릭을 받도록 한다.
struct CompanionSpriteMask: Equatable {
    let columns: Int
    let rows: Int
    /// row-major. true 면 그 칸에 그려진 픽셀이 있다.
    let filled: [Bool]

    var filledCellCount: Int { filled.lazy.filter { $0 }.count }

    /// 전체를 덮는 마스크. 스프라이트를 읽지 못했을 때의 안전한 기본값이다.
    static func full(columns: Int, rows: Int) -> CompanionSpriteMask {
        CompanionSpriteMask(
            columns: columns,
            rows: rows,
            filled: Array(repeating: true, count: max(0, columns * rows))
        )
    }

    func isFilled(column: Int, row: Int) -> Bool {
        guard column >= 0, column < columns, row >= 0, row < rows else { return false }
        return filled[row * columns + column]
    }

    /// 두 마스크를 합친다. 프레임마다 판정이 흔들리지 않도록 애니메이션 전체를 합쳐서 쓴다.
    func union(_ other: CompanionSpriteMask) -> CompanionSpriteMask {
        guard columns == other.columns, rows == other.rows else { return self }
        return CompanionSpriteMask(
            columns: columns,
            rows: rows,
            filled: zip(filled, other.filled).map { $0 || $1 }
        )
    }
}

enum CompanionSpriteMetrics {
    /// 클릭 판정 격자의 촘촘함. 96×104pt 스프라이트에서 한 칸이 약 4pt 다.
    static let maskColumns = 24
    static let maskRows = 26

    /// 픽셀 알파를 읽어 격자 마스크를 만든다.
    /// 한 칸 안에 그려진 픽셀이 하나라도 있으면 그 칸을 클릭 영역에 포함한다.
    static func mask(
        width: Int,
        height: Int,
        columns: Int = maskColumns,
        rows: Int = maskRows,
        isOpaque: (Int, Int) -> Bool
    ) -> CompanionSpriteMask {
        guard width > 0, height > 0, columns > 0, rows > 0 else {
            return .full(columns: columns, rows: rows)
        }

        var filled = Array(repeating: false, count: columns * rows)
        for y in 0..<height {
            let row = min(rows - 1, y * rows / height)
            for x in 0..<width where isOpaque(x, y) {
                let column = min(columns - 1, x * columns / width)
                filled[row * columns + column] = true
            }
        }

        // 전부 투명하면 클릭 영역이 사라지므로 전체를 덮는다.
        guard filled.contains(true) else { return .full(columns: columns, rows: rows) }
        return CompanionSpriteMask(columns: columns, rows: rows, filled: filled)
    }

    static func union(_ masks: [CompanionSpriteMask]) -> CompanionSpriteMask {
        guard let first = masks.first else {
            return .full(columns: maskColumns, rows: maskRows)
        }
        return masks.dropFirst().reduce(first) { $0.union($1) }
    }
}
