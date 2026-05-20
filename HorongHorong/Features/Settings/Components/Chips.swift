import SwiftUI

// MARK: - Keyword chip

/// 단순 라벨 + × 의 chip. 관심 키워드 표시에 사용.
struct KeywordChip: View {
    var label: String
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Source chip

/// 뉴스 소스 타입별 chip. 좌측에 타입 아이콘, 라벨, 선택적 카운트, 우측 × 삭제.
struct SourceChip: View {
    var icon: SourceChipIcon
    var label: String
    var count: Int?
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    iconView
                    Text(label)
                        .font(.caption.weight(.medium))
                    if let count, count > 1 {
                        Text("- \(count)개")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        Text(icon.glyph)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(icon.color)
            )
    }
}

enum SourceChipIcon {
    case youtube
    case googleNews
    case hackerNews
    case yozmIT
    case rss

    var glyph: String {
        switch self {
        case .youtube:    return "Y"
        case .googleNews: return "G"
        case .hackerNews: return "H"
        case .yozmIT:     return "요"
        case .rss:        return "R"
        }
    }

    var color: Color {
        switch self {
        case .youtube:    return Color(red: 0.95, green: 0.20, blue: 0.20)
        case .googleNews: return Color(red: 0.20, green: 0.45, blue: 0.95)
        case .hackerNews: return Color(red: 0.95, green: 0.45, blue: 0.10)
        case .yozmIT:     return Color(red: 0.20, green: 0.70, blue: 0.40)
        case .rss:        return Color(red: 0.95, green: 0.55, blue: 0.10)
        }
    }
}

// MARK: - FlowLayout

/// chip 을 가로로 채우다가 줄바꿈 처리하는 단순 FlowLayout. macOS 14+.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let layout = arrange(subviews: subviews, in: maxWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : layout.maxX, height: layout.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews: subviews, in: bounds.width)
        for (index, position) in layout.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.minX, y: bounds.minY + position.minY),
                proposal: ProposedViewSize(width: position.width, height: position.height)
            )
        }
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> (positions: [CGRect], maxX: CGFloat, maxY: CGFloat) {
        var positions: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (positions, maxX, y + rowHeight)
    }
}
