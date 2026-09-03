import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 여정 화면(나무·걷는 사람·이정표).

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementJourneyScene: View {
    let role: AchievementRole
    let destinationImageURL: URL?
    let milestones: [AchievementGoal?]

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let cappedPhase = walkerPhase
                let walkerPoint = routePoint(at: cappedPhase, in: size)
                let beamPoint = routePoint(at: min(1, cappedPhase + 0.08), in: size)
                let destinationPoint = CGPoint(x: size.width - 72, y: size.height * 0.31)
                let frameIndex = Int(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.75) / 0.25)

                ZStack {
                    journeyBackground(in: size)

                    forestLayer(in: size)
                    groundLayer(in: size)
                    pathGroundLayer(in: size)
                    fireflyLayer(in: size, date: context.date)

                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 42, nearWidth: 4, capDepth: 24)
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.22).opacity(0.28))
                        .blur(radius: 18)
                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 30, nearWidth: 2.8, capDepth: 18)
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.31))
                        .blur(radius: 7)
                    lanternBeam(from: walkerPoint, to: beamPoint, farWidth: 15, nearWidth: 1.7, capDepth: 10)
                        .fill(Color(red: 1.0, green: 0.90, blue: 0.48).opacity(0.18))
                        .blur(radius: 2)
                    lanternGlow(from: walkerPoint, to: beamPoint)

                    routePath(in: size)
                        .stroke(Color(red: 0.10, green: 0.07, blue: 0.04).opacity(0.54), style: StrokeStyle(lineWidth: 31, lineCap: .round, lineJoin: .round))
                        .blur(radius: 0.4)
                    routePath(in: size)
                        .stroke(Color(red: 0.68, green: 0.42, blue: 0.17).opacity(0.88), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
                    routePath(in: size)
                        .stroke(Color(red: 0.96, green: 0.66, blue: 0.32).opacity(0.48), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    completedRoutePath(in: size)
                        .stroke(Color(red: 1.0, green: 0.73, blue: 0.38).opacity(0.66), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color(red: 1.0, green: 0.58, blue: 0.24).opacity(0.42), radius: 7, x: 0, y: 0)

                    unexploredFogLayer(in: size)

                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, goal in
                        let point = routePoint(at: milestonePhase(index, total: milestones.count), in: size)
                        AchievementJourneyMilestone(goal: goal, index: index, isLit: (slotFractions[index] ?? 0) >= 1)
                            .position(x: point.x, y: point.y - 54)
                    }

                    AchievementJourneyDestination(role: role, imageURL: destinationImageURL)
                        .position(destinationPoint)

                    AchievementJourneyWalker(frameIndex: frameIndex)
                        .position(walkerPoint)

                    Text("“\(visionQuote)”")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(Color(red: 0.80, green: 0.76, blue: 0.67).opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.32), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: min(460, size.width - 56))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 19)
                }
                .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PopoverChrome.radius(18), style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var visionQuote: String {
        let trimmed = role.vision.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "오늘의 일이 목적지로 이어진다" : trimmed
    }

    /// 깃발 슬롯별 하위 목표 달성률. 비어 있는 슬롯은 nil.
    private var slotFractions: [Double?] {
        milestones.map { goal in
            guard let goal else { return nil }
            guard goal.total > 0 else { return goal.done > 0 ? 1 : 0 }
            return min(1, Double(goal.done) / Double(goal.total))
        }
    }

    /// 지정된 깃발을 순서대로 지나며, 각 구간을 해당 목표의 하위 목표 달성률만큼만 전진한다.
    /// 하위 목표를 모두 달성한 깃발에서만 다음 구간으로 넘어간다.
    private var walkerPhase: CGFloat {
        let startPhase: CGFloat = 0.04
        var current = startPhase
        let total = milestones.count

        for (index, fraction) in slotFractions.enumerated() {
            guard let fraction else { continue }
            let target = milestonePhase(index, total: total)
            guard target > current else { continue }
            if fraction >= 1 {
                current = target
            } else {
                return min(0.96, current + (target - current) * CGFloat(max(0, fraction)))
            }
        }

        return min(0.96, current)
    }

    private var starPositions: [CGPoint] {
        [
            CGPoint(x: 0.10, y: 0.17),
            CGPoint(x: 0.18, y: 0.28),
            CGPoint(x: 0.30, y: 0.14),
            CGPoint(x: 0.42, y: 0.24),
            CGPoint(x: 0.57, y: 0.12),
            CGPoint(x: 0.66, y: 0.30),
            CGPoint(x: 0.74, y: 0.18),
            CGPoint(x: 0.84, y: 0.33),
            CGPoint(x: 0.92, y: 0.15),
            CGPoint(x: 0.25, y: 0.40),
            CGPoint(x: 0.52, y: 0.38),
            CGPoint(x: 0.70, y: 0.46),
        ]
    }

    private var fireflyPositions: [CGPoint] {
        [
            CGPoint(x: 0.14, y: 0.23),
            CGPoint(x: 0.32, y: 0.36),
            CGPoint(x: 0.45, y: 0.64),
            CGPoint(x: 0.59, y: 0.25),
            CGPoint(x: 0.69, y: 0.40),
            CGPoint(x: 0.88, y: 0.52),
            CGPoint(x: 0.18, y: 0.58),
            CGPoint(x: 0.76, y: 0.70),
        ]
    }

    private func journeyBackground(in size: CGSize) -> some View {
        return ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.07)

            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.15, blue: 0.23),
                    Color(red: 0.07, green: 0.14, blue: 0.17),
                    Color(red: 0.05, green: 0.10, blue: 0.09),
                    Color(red: 0.05, green: 0.08, blue: 0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.23, blue: 0.32).opacity(0.95),
                    .clear,
                ],
                center: UnitPoint(x: 0.78, y: -0.10),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.65
            )

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.87, green: 0.92, blue: 1.0).opacity(index % 3 == 0 ? 0.72 : 0.38))
                    .frame(width: index % 4 == 0 ? 2.5 : 1.7, height: index % 4 == 0 ? 2.5 : 1.7)
                    .position(
                        x: size.width * starPositions[index].x,
                        y: size.height * starPositions[index].y
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.99, green: 0.96, blue: 0.88),
                            Color(red: 0.91, green: 0.85, blue: 0.66),
                            Color(red: 0.72, green: 0.68, blue: 0.53),
                        ],
                        center: UnitPoint(x: 0.38, y: 0.38),
                        startRadius: 0,
                        endRadius: 28
                    )
                )
                .frame(width: 54, height: 54)
                .shadow(color: Color(red: 0.97, green: 0.93, blue: 0.78).opacity(0.25), radius: 28, x: 0, y: 0)
                .position(x: size.width * 0.89 - 27, y: 49)

            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.42),
                ],
                center: .center,
                startRadius: min(size.width, size.height) * 0.18,
                endRadius: max(size.width, size.height) * 0.68
            )
        }
    }

    private func forestLayer(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let x = size.width * (CGFloat(index) / 11.0)
                let height = size.height * (0.30 + CGFloat(index % 4) * 0.045)
                AchievementJourneyTreeShape()
                    .fill(Color(red: 0.03, green: 0.09, blue: 0.06).opacity(0.72))
                    .frame(width: 76 + CGFloat(index % 3) * 16, height: height)
                    .position(x: x, y: size.height - 96 - height * 0.22)
            }

            ForEach(0..<9, id: \.self) { index in
                let x = size.width * (CGFloat(index) / 8.0)
                let height = size.height * (0.36 + CGFloat(index % 3) * 0.055)
                AchievementJourneyTreeShape()
                    .fill(Color(red: 0.02, green: 0.07, blue: 0.05).opacity(0.90))
                    .frame(width: 96 + CGFloat(index % 2) * 24, height: height)
                    .position(x: x + CGFloat(index % 2) * 24 - 10, y: size.height - 74 - height * 0.20)
            }

            AchievementJourneySideTrunkShape()
                .fill(Color.black.opacity(0.22))
                .frame(width: 98, height: size.height * 0.72)
                .position(x: 18, y: size.height * 0.50)
            AchievementJourneySideTrunkShape()
                .fill(Color.black.opacity(0.20))
                .frame(width: 102, height: size.height * 0.76)
                .scaleEffect(x: -1, y: 1)
                .position(x: size.width - 16, y: size.height * 0.48)
        }
    }

    private func groundLayer(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.07),
                    Color(red: 0.04, green: 0.07, blue: 0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(116, size.height * 0.34))
        }
    }

    private func pathGroundLayer(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.22, green: 0.19, blue: 0.12).opacity(0.65),
                        Color(red: 0.13, green: 0.11, blue: 0.07).opacity(0.52),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.58
                )
            )
            .frame(width: size.width * 1.18, height: min(92, size.height * 0.28))
            .position(x: size.width * 0.50, y: size.height - 12)
            .blur(radius: 1)
            .opacity(0.65)
    }

    private func fireflyLayer(in size: CGSize, date: Date) -> some View {
        let time = CGFloat(date.timeIntervalSinceReferenceDate)

        return ZStack {
            ForEach(0..<fireflyPositions.count, id: \.self) { index in
                let base = fireflyPositions[index]
                let speed = CGFloat(0.42 + Double(index % 4) * 0.07)
                let driftX = sin(time * speed + CGFloat(index) * 1.7) * CGFloat(8 + (index % 3) * 4)
                let driftY = cos(time * (speed * 0.82) + CGFloat(index) * 1.3) * CGFloat(5 + (index % 2) * 4)
                let pulse = 0.42 + 0.42 * (sin(time * (speed * 2.2) + CGFloat(index)) + 1) / 2

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.34).opacity(0.42),
                                    Color(red: 1.0, green: 0.58, blue: 0.18).opacity(0.12),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 17
                            )
                        )
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.88, blue: 0.45).opacity(0.90))
                        .frame(width: 3.2, height: 3.2)
                }
                .opacity(pulse)
                .position(
                    x: size.width * base.x + driftX,
                    y: size.height * base.y + driftY
                )
            }
        }
    }

    private func unexploredFogLayer(in size: CGSize) -> some View {
        let clampedProgress = walkerPhase
        let width = size.width * max(0.18, 1 - clampedProgress + 0.08)
        let centerX = size.width - width / 2

        return LinearGradient(
            colors: [
                .clear,
                Color(red: 0.02, green: 0.04, blue: 0.04).opacity(0.52),
                Color(red: 0.02, green: 0.035, blue: 0.03).opacity(0.80),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: size.height)
        .position(x: centerX, y: size.height / 2)
    }

    private func routePath(in size: CGSize) -> Path {
        var path = Path()
        let p0 = CGPoint(x: size.width * 0.06, y: size.height * 0.72)
        let p1 = CGPoint(x: size.width * 0.30, y: size.height * 0.48)
        let p2 = CGPoint(x: size.width * 0.52, y: size.height * 0.76)
        let p3 = CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        let p4 = CGPoint(x: size.width * 0.94, y: size.height * 0.50)
        path.move(to: p0)
        path.addCurve(
            to: p1,
            control1: CGPoint(x: size.width * 0.14, y: size.height * 0.68),
            control2: CGPoint(x: size.width * 0.20, y: size.height * 0.44)
        )
        path.addCurve(
            to: p2,
            control1: CGPoint(x: size.width * 0.38, y: size.height * 0.42),
            control2: CGPoint(x: size.width * 0.40, y: size.height * 0.82)
        )
        path.addCurve(
            to: p3,
            control1: CGPoint(x: size.width * 0.59, y: size.height * 0.78),
            control2: CGPoint(x: size.width * 0.59, y: size.height * 0.60)
        )
        path.addCurve(
            to: p4,
            control1: CGPoint(x: size.width * 0.76, y: size.height * 0.42),
            control2: CGPoint(x: size.width * 0.82, y: size.height * 0.56)
        )
        return path
    }

    private func completedRoutePath(in size: CGSize) -> Path {
        var path = Path()
        let clampedProgress = walkerPhase
        path.move(to: routePoint(at: 0, in: size))
        let steps = max(2, Int(clampedProgress * 40))
        for step in 1...steps {
            let phase = clampedProgress * CGFloat(step) / CGFloat(steps)
            path.addLine(to: routePoint(at: phase, in: size))
        }
        return path
    }

    private func routePoint(at phase: CGFloat, in size: CGSize) -> CGPoint {
        let clamped = max(0, min(1, phase))
        let scaled = clamped * 4
        let segment = min(3, Int(scaled))
        let t = scaled - CGFloat(segment)

        let p0 = CGPoint(x: size.width * 0.06, y: size.height * 0.72)
        let p1 = CGPoint(x: size.width * 0.30, y: size.height * 0.48)
        let p2 = CGPoint(x: size.width * 0.52, y: size.height * 0.76)
        let p3 = CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        let p4 = CGPoint(x: size.width * 0.94, y: size.height * 0.50)

        switch segment {
        case 0:
            return cubic(
                t,
                p0,
                CGPoint(x: size.width * 0.14, y: size.height * 0.68),
                CGPoint(x: size.width * 0.20, y: size.height * 0.44),
                p1
            )
        case 1:
            return cubic(
                t,
                p1,
                CGPoint(x: size.width * 0.38, y: size.height * 0.42),
                CGPoint(x: size.width * 0.40, y: size.height * 0.82),
                p2
            )
        case 2:
            return cubic(
                t,
                p2,
                CGPoint(x: size.width * 0.59, y: size.height * 0.78),
                CGPoint(x: size.width * 0.59, y: size.height * 0.60),
                p3
            )
        default:
            return cubic(
                t,
                p3,
                CGPoint(x: size.width * 0.76, y: size.height * 0.42),
                CGPoint(x: size.width * 0.82, y: size.height * 0.56),
                p4
            )
        }
    }

    private func milestonePhase(_ index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 0.50 }
        let start: CGFloat = 0.14
        let end: CGFloat = 0.82
        return start + (end - start) * CGFloat(index) / CGFloat(total - 1)
    }

    private func lanternBeam(
        from start: CGPoint,
        to end: CGPoint,
        farWidth: CGFloat,
        nearWidth: CGFloat,
        capDepth: CGFloat
    ) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let axis = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let nearCenter = CGPoint(x: start.x + axis.x * 4, y: start.y + axis.y * 4)
        let mid = CGPoint(x: start.x + dx * 0.56, y: start.y + dy * 0.56)
        let capCenter = CGPoint(x: end.x + axis.x * capDepth, y: end.y + axis.y * capDepth)
        let farTop = CGPoint(x: end.x + normal.x * farWidth, y: end.y + normal.y * farWidth)
        let farBottom = CGPoint(x: end.x - normal.x * farWidth, y: end.y - normal.y * farWidth)
        let nearTop = CGPoint(x: nearCenter.x + normal.x * nearWidth, y: nearCenter.y + normal.y * nearWidth)
        let nearBottom = CGPoint(x: nearCenter.x - normal.x * nearWidth, y: nearCenter.y - normal.y * nearWidth)

        var path = Path()
        path.move(to: nearTop)
        path.addCurve(
            to: farTop,
            control1: CGPoint(x: start.x + axis.x * 18 + normal.x * nearWidth * 1.4, y: start.y + axis.y * 18 + normal.y * nearWidth * 1.4),
            control2: CGPoint(x: mid.x + normal.x * farWidth * 0.94, y: mid.y + normal.y * farWidth * 0.94)
        )
        path.addCurve(
            to: farBottom,
            control1: CGPoint(x: capCenter.x + normal.x * farWidth * 0.28, y: capCenter.y + normal.y * farWidth * 0.28),
            control2: CGPoint(x: capCenter.x - normal.x * farWidth * 0.28, y: capCenter.y - normal.y * farWidth * 0.28)
        )
        path.addCurve(
            to: nearBottom,
            control1: CGPoint(x: mid.x - normal.x * farWidth * 0.94, y: mid.y - normal.y * farWidth * 0.94),
            control2: CGPoint(x: start.x + axis.x * 18 - normal.x * nearWidth * 1.4, y: start.y + axis.y * 18 - normal.y * nearWidth * 1.4)
        )
        path.closeSubpath()
        return path
    }

    private func lanternGlow(from start: CGPoint, to end: CGPoint) -> some View {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let point = CGPoint(x: end.x + dx / length * 13, y: end.y + dy / length * 13)
        let angle = Angle(radians: Double(atan2(dy, dx)) + .pi / 2)

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.83, blue: 0.35).opacity(0.44),
                            Color(red: 1.0, green: 0.56, blue: 0.18).opacity(0.22),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 38
                    )
                )
                .frame(width: 78, height: 54)
                .blur(radius: 3)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.76, blue: 0.32).opacity(0.20))
                .frame(width: 43, height: 28)
                .blur(radius: 7)
        }
        .rotationEffect(angle)
        .position(point)
    }

    private func cubic(_ t: CGFloat, _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        let x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x
        let y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

struct AchievementJourneyTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let bottom = rect.maxY
        let trunkWidth = rect.width * 0.11
        let canopyWidth = rect.width

        path.addRoundedRect(
            in: CGRect(
                x: centerX - trunkWidth / 2,
                y: rect.minY + rect.height * 0.30,
                width: trunkWidth,
                height: rect.height * 0.70
            ),
            cornerSize: CGSize(width: trunkWidth * 0.35, height: trunkWidth * 0.35)
        )

        path.move(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.42, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.28, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.48, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.18, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: centerX - canopyWidth * 0.46, y: bottom * 0.92))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.46, y: bottom * 0.92))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.18, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.48, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.28, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: centerX + canopyWidth * 0.42, y: rect.minY + rect.height * 0.42))
        path.closeSubpath()

        return path
    }
}

struct AchievementJourneySideTrunkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.height * 0.70),
            control2: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.height * 0.24)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY),
            control1: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.height * 0.30),
            control2: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.height * 0.74)
        )
        path.closeSubpath()
        return path
    }
}

struct AchievementJourneyWalker: View {
    let frameIndex: Int

    var body: some View {
        ZStack {
            Image("HorongJourney\(min(max(frameIndex, 0), 2) + 1)")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
        }
        .frame(width: 88, height: 88)
    }
}

struct AchievementJourneyDestination: View {
    let role: AchievementRole
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.035).opacity(0.86))
                if let imageURL, let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                } else {
                    Image("AchievementJourneyDefault")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())
                }
            }
            .frame(width: 70, height: 70)
            .overlay(Circle().stroke(Color(red: 0.66, green: 0.58, blue: 0.44).opacity(0.90), lineWidth: 3))
            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1).padding(5))
            .shadow(color: .black.opacity(0.48), radius: 11, x: 0, y: 7)

            Text("되고 싶은 나")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.80))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.48), in: Capsule())
        }
        .accessibilityLabel("되고 싶은 나, \(role.name)")
    }
}

struct AchievementJourneyMilestone: View {
    let goal: AchievementGoal?
    let index: Int
    let isLit: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: goal == nil ? "flag" : "flag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(flagColor)
                .shadow(color: shadowColor, radius: 6, x: 0, y: 0)
            Text(goal?.title ?? "\(index + 1)번 목표")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(goal == nil ? .white.opacity(0.54) : .white.opacity(0.86))
                .lineLimit(1)
                .frame(width: 82)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous))
    }

    private var flagColor: Color {
        guard let goal else { return Color.white.opacity(0.36) }
        return isLit ? goal.color : Color.white.opacity(0.38)
    }

    private var shadowColor: Color {
        guard let goal, isLit else { return .clear }
        return goal.color.opacity(0.45)
    }
}

struct AchievementJourneyStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

struct AchievementJourneyActionStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isPrimary ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(10), style: .continuous)
                    .fill(isPrimary ? PopoverChrome.primaryButtonFill : AnyShapeStyle(PopoverChrome.surfaceAlt))
            }
            .opacity(isPrimary ? 0.55 : 1)
            .buttonStyle(.plain)
    }
}

extension View {
    func achievementJourneyActionStyle(isPrimary: Bool) -> some View {
        modifier(AchievementJourneyActionStyle(isPrimary: isPrimary))
    }
}
