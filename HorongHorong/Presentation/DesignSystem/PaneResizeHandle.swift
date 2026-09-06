import AppKit
import SwiftUI

/// 좌우로 나뉜 두 칸 중 **오른쪽 칸**의 너비를 정한다.
///
/// **저장값을 그대로 쓰지 않는다.** 창을 줄이면 어제 저장한 너비가 오늘은 화면을 넘길 수 있으므로
/// 그릴 때마다 지금 창 크기로 다시 자른다. `totalWidth` 를 주입받는 이유도 그래서다 —
/// 창이 좁아졌을 때의 동작을 창 없이 테스트할 수 있어야 한다.
enum PaneWidthPolicy {
    /// - Parameters:
    ///   - proposed: 저장했거나 지금 끌고 있는 너비.
    ///   - totalWidth: 두 칸이 나눠 쓸 전체 너비.
    ///   - leadingMinimum: 왼쪽 칸이 최소한 지켜야 할 너비.
    ///   - trailingMinimum: 오른쪽 칸이 최소한 지켜야 할 너비.
    ///   - trailingMaximum: 오른쪽 칸이 넘지 못할 너비.
    static func resolveTrailing(
        proposed: CGFloat,
        totalWidth: CGFloat,
        leadingMinimum: CGFloat,
        trailingMinimum: CGFloat,
        trailingMaximum: CGFloat
    ) -> CGFloat {
        let available = max(0, totalWidth.isFinite ? totalWidth : 0)
        let lowerBound = min(trailingMinimum, trailingMaximum)
        let upperBound = min(trailingMaximum, available - leadingMinimum)

        // 창이 두 칸의 최소 너비조차 담지 못하는 상황. 한쪽을 0 으로 만들지 않고
        // 남은 자리를 최소 너비 비율대로 나눠 둘 다 형태를 유지하게 한다.
        guard upperBound > lowerBound else {
            let totalMinimum = leadingMinimum + trailingMinimum
            guard totalMinimum > 0 else { return 0 }
            return min(available, available * (trailingMinimum / totalMinimum))
        }

        guard proposed.isFinite else { return lowerBound }
        return min(max(proposed, lowerBound), upperBound)
    }
}

/// 두 칸 사이에서 좌우로 끌어 너비를 조절하는 손잡이.
///
/// 1pt 짜리 구분선만 두면 손으로 집기 어려워 실제 폭은 `hitWidth` 만큼 잡고 선은 가운데 그린다.
struct PaneResizeHandle: View {
    /// 끌기 시작점 기준 이동 거리. 왼쪽이 음수, 오른쪽이 양수다.
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    private let hitWidth: CGFloat = 7

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var isCursorPushed = false

    var body: some View {
        Rectangle()
            .fill(isHighlighted ? PopoverChrome.accent.opacity(0.55) : PopoverChrome.divider)
            .frame(width: isHighlighted ? 2 : 1)
            .frame(width: hitWidth)
            .frame(maxHeight: .infinity)
            .background(PopoverChrome.surface)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    pushCursor()
                } else if !isDragging {
                    popCursor()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        pushCursor()
                        onDrag(value.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDragEnd()
                        if !isHovering { popCursor() }
                    }
            )
            .onDisappear {
                // 손잡이 위에 커서를 둔 채 화면이 바뀌면 `onHover(false)` 가 오지 않는다.
                // 그대로 두면 앱 전체에 좌우 화살표 커서가 남는다.
                popCursor()
            }
            .accessibilityLabel("칸 너비 조절")
    }

    private var isHighlighted: Bool { isHovering || isDragging }

    private func pushCursor() {
        guard !isCursorPushed else { return }
        NSCursor.resizeLeftRight.push()
        isCursorPushed = true
    }

    private func popCursor() {
        guard isCursorPushed else { return }
        NSCursor.pop()
        isCursorPushed = false
    }
}
