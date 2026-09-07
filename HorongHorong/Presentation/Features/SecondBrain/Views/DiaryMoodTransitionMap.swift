import SwiftUI

/// 감정 전이 지도. 일곱 감정 영역을 원에 놓고 «무엇 뒤에 무엇이 왔는가» 를 호로 잇는다.
///
/// Swift Charts 가 아니라 `Canvas` 로 그린다 — 차트 축 위에 올릴 수 있는 그림이 아니고,
/// 호·화살촉·노드를 한 번의 패스로 그리는 편이 마크를 수십 개 쌓는 것보다 가볍다.
struct DiaryMoodTransitionMap: View, Equatable {
    let transitions: [DiaryMoodTransition]
    let points: [DiaryMoodPoint]
    var height: CGFloat = 200

    nonisolated static func == (lhs: DiaryMoodTransitionMap, rhs: DiaryMoodTransitionMap) -> Bool {
        lhs.transitions == rhs.transitions && lhs.points == rhs.points && lhs.height == rhs.height
    }

    var body: some View {
        if transitions.isEmpty {
            DiaryInsightEmpty(message: emptyMessage)
        } else {
            Canvas { context, size in draw(in: &context, size: size) }
                .frame(height: height)
                .accessibilityLabel("감정 전이 지도")
                .accessibilityValue(summaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text("선 굵기 = 전이 횟수 · 화살표 = 방향")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                ForEach(transitions.prefix(3)) { transition in
                    Text("\(transition.from.emoji) \(transition.from.shortTitle) → \(transition.to.emoji) \(transition.to.shortTitle)  \(transition.count)번")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
            }
        }
    }

    // MARK: - 그리기

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - nodeMaximumRadius - 10
        guard radius > 0 else { return }

        let positions = nodePositions(center: center, radius: radius)
        let maximumCount = transitions.map(\.count).max() ?? 1

        for transition in transitions {
            guard let from = positions[transition.from], let to = positions[transition.to] else { continue }
            let weight = Double(transition.count) / Double(maximumCount)
            drawChord(
                in: &context,
                from: from,
                to: to,
                fromRadius: nodeRadius(for: transition.from),
                toRadius: nodeRadius(for: transition.to),
                center: center,
                color: transition.from.chartColor,
                weight: weight
            )
        }

        for group in DiaryMoodGroup.allCases {
            guard let position = positions[group] else { continue }
            drawNode(in: &context, group: group, at: position)
        }
    }

    /// 호는 원 중심 쪽으로 휜다. 직선으로 이으면 마주 보는 두 감정의 선이 중앙에서 전부 겹친다.
    ///
    /// **양 끝을 노드 반지름만큼 잘라 낸다.** 중심에서 중심으로 그으면 선의 끝과 화살촉이
    /// 노드 원 밑에 깔려 «어느 쪽으로 흘렀는지» 가 보이지 않는다.
    private func drawChord(
        in context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        fromRadius: CGFloat,
        toRadius: CGFloat,
        center: CGPoint,
        color: Color,
        weight: Double
    ) {
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let control = CGPoint(
            x: midpoint.x + (center.x - midpoint.x) * 0.55,
            y: midpoint.y + (center.y - midpoint.y) * 0.55
        )

        // 곡선은 끝점 근처에서 제어점 쪽을 향하므로, 그 방향으로 반지름만큼 물러나면
        // 원 둘레에 거의 정확히 닿는다.
        let start = advance(from, toward: control, by: fromRadius)
        let arrowTip = advance(to, toward: control, by: toRadius + 2)
        // 선은 화살촉이 시작하는 자리에서 끝낸다 — 삼각형 밑을 지나가면 뭉툭해 보인다.
        let lineEnd = advance(arrowTip, toward: control, by: arrowLength * 0.8)

        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: lineEnd, control: control)
        context.stroke(
            path,
            with: .color(color.opacity(0.34 + weight * 0.5)),
            style: StrokeStyle(lineWidth: 1.2 + weight * 3.2, lineCap: .round)
        )

        drawArrowHead(
            in: &context,
            tip: arrowTip,
            towardControl: control,
            color: color.opacity(0.8 + weight * 0.2)
        )
    }

    /// 화살촉. **선보다 넉넉하게 그린다** — 방향을 읽는 것은 선이 아니라 이 삼각형이다.
    private func drawArrowHead(
        in context: inout GraphicsContext,
        tip: CGPoint,
        towardControl control: CGPoint,
        color: Color
    ) {
        // 제어점에서 끝점으로 들어오는 방향이 곧 곡선이 도착하는 방향이다.
        guard let unit = direction(from: control, to: tip) else { return }
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let base = CGPoint(x: tip.x - unit.x * arrowLength, y: tip.y - unit.y * arrowLength)
        let half = arrowWidth / 2

        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: base.x + normal.x * half, y: base.y + normal.y * half))
        head.addLine(to: CGPoint(x: base.x - normal.x * half, y: base.y - normal.y * half))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: - 기하

    private var arrowLength: CGFloat { 11 }
    private var arrowWidth: CGFloat { 9 }

    private func direction(from origin: CGPoint, to target: CGPoint) -> CGPoint? {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.001 else { return nil }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func advance(_ point: CGPoint, toward target: CGPoint, by distance: CGFloat) -> CGPoint {
        guard let unit = direction(from: point, to: target) else { return point }
        return CGPoint(x: point.x + unit.x * distance, y: point.y + unit.y * distance)
    }

    private func drawNode(in context: inout GraphicsContext, group: DiaryMoodGroup, at position: CGPoint) {
        let radius = nodeRadius(for: group)
        let rect = CGRect(
            x: position.x - radius,
            y: position.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: rect), with: .color(group.chartColor.opacity(0.22)))
        context.stroke(Path(ellipseIn: rect), with: .color(group.chartColor.opacity(0.8)), lineWidth: 1.2)
        context.draw(
            Text(group.emoji).font(.system(size: 13)),
            at: position
        )
    }

    // MARK: - 좌표

    private let nodeMinimumRadius: CGFloat = 11
    private let nodeMaximumRadius: CGFloat = 18

    private func nodePositions(center: CGPoint, radius: CGFloat) -> [DiaryMoodGroup: CGPoint] {
        let groups = DiaryMoodGroup.allCases
        var positions: [DiaryMoodGroup: CGPoint] = [:]
        for (index, group) in groups.enumerated() {
            // 12시 방향에서 시작해 시계 방향으로 균등 배치한다.
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(groups.count)
            positions[group] = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }
        return positions
    }

    /// 노드 크기는 그 감정이 몇 번 나타났는지에 비례한다.
    private func nodeRadius(for group: DiaryMoodGroup) -> CGFloat {
        let counts = Dictionary(grouping: points, by: { $0.mood.group }).mapValues(\.count)
        let maximum = counts.values.max() ?? 1
        guard maximum > 0, let count = counts[group] else { return nodeMinimumRadius }
        let ratio = CGFloat(count) / CGFloat(maximum)
        return nodeMinimumRadius + (nodeMaximumRadius - nodeMinimumRadius) * ratio
    }

    private var summaryText: String {
        transitions.prefix(3)
            .map { "\($0.from.shortTitle)에서 \($0.to.shortTitle)로 \($0.count)번" }
            .joined(separator: ", ")
    }

    private var emptyMessage: String {
        points.count < 2
            ? "흐름을 보려면 기록이 조금 더 필요해요"
            : "아직 감정이 바뀐 적이 없어요"
    }
}
