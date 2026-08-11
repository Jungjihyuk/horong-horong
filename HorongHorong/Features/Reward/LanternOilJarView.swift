import SwiftUI

// MARK: - 등불 조각들
//
// 앱 컨셉인 등불을 SwiftUI 도형으로 그린다.
// 위에서부터 불꽃 · 심지 · 버너 목 · 기름통 · 받침 기둥 · 굽이고,
// 기름통이 기름(포인트)이 차오르는 자리다.

/// 등불 전체에서 각 부분이 차지하는 세로 비율.
private enum LanternMetrics {
    /// 불꽃이 설 자리. 불이 꺼져 있으면 비어 있다.
    static let wickTop: CGFloat = 0.17
    static let burnerTop: CGFloat = 0.21
    static let fontTop: CGFloat = 0.28
    static let fontBottom: CGFloat = 0.74
    static let stemBottom: CGFloat = 0.87

    static var fontHeightRatio: CGFloat { fontBottom - fontTop }
}

/// 기름이 차오르는 기름통. 위아래가 좁고 가운데가 부푼 등잔 몸체.
private struct LanternGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let top = rect.minY
        let bottom = rect.maxY
        let h = bottom - top

        var path = Path()
        path.move(to: CGPoint(x: w * 0.37, y: top))
        path.addLine(to: CGPoint(x: w * 0.63, y: top))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.88, y: top + h * 0.46),
            control: CGPoint(x: w * 0.92, y: top + h * 0.13)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.60, y: bottom),
            control: CGPoint(x: w * 0.85, y: bottom - h * 0.10)
        )
        path.addLine(to: CGPoint(x: w * 0.40, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.12, y: top + h * 0.46),
            control: CGPoint(x: w * 0.15, y: bottom - h * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.37, y: top),
            control: CGPoint(x: w * 0.08, y: top + h * 0.13)
        )
        path.closeSubpath()
        return path
    }
}

/// 버너 목·심지 조절 손잡이·받침 기둥·굽. 금속으로 칠하는 부분을 한 번에 그린다.
private struct LanternMetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func y(_ ratio: CGFloat) -> CGFloat { rect.minY + h * ratio }

        var path = Path()

        // 버너 목 — 심지가 나오는 금속 테. 위가 좁고 아래가 벌어진다.
        path.move(to: CGPoint(x: w * 0.41, y: y(LanternMetrics.burnerTop)))
        path.addLine(to: CGPoint(x: w * 0.59, y: y(LanternMetrics.burnerTop)))
        path.addLine(to: CGPoint(x: w * 0.66, y: y(LanternMetrics.fontTop) + h * 0.01))
        path.addLine(to: CGPoint(x: w * 0.34, y: y(LanternMetrics.fontTop) + h * 0.01))
        path.closeSubpath()

        // 심지 조절 손잡이
        path.addEllipse(in: CGRect(x: w * 0.64, y: y(0.245), width: w * 0.11, height: h * 0.028))

        // 받침 기둥 — 아래로 갈수록 벌어진다.
        path.move(to: CGPoint(x: w * 0.40, y: y(LanternMetrics.fontBottom) - h * 0.01))
        path.addLine(to: CGPoint(x: w * 0.60, y: y(LanternMetrics.fontBottom) - h * 0.01))
        path.addLine(to: CGPoint(x: w * 0.66, y: y(LanternMetrics.stemBottom)))
        path.addLine(to: CGPoint(x: w * 0.34, y: y(LanternMetrics.stemBottom)))
        path.closeSubpath()

        // 굽
        path.addRoundedRect(
            in: CGRect(x: w * 0.24, y: y(LanternMetrics.stemBottom), width: w * 0.52, height: h * 0.07),
            cornerSize: CGSize(width: 4, height: 4)
        )

        return path
    }
}

/// 심지 위에서 타는 불꽃. 위로 뾰족하고 아래는 둥글다.
private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.62),
            control: CGPoint(x: w * 0.88, y: h * 0.28)
        )
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: h),
            control: CGPoint(x: w, y: h * 0.94)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.62),
            control: CGPoint(x: 0, y: h * 0.94)
        )
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: 0),
            control: CGPoint(x: w * 0.12, y: h * 0.28)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - 랜턴

/// 모은 포인트를 랜턴의 기름으로 보여준다.
/// 기름은 유리구에 차오르고, 불은 월간 목표를 달성해야 붙는다.
struct LanternOilJarView: View {
    let progress: RewardProgress
    /// 달성했지만 아직 보상을 안 고른 월간 목표 이름들.
    /// 기름(포인트)이 아무리 차도 이게 비어 있으면 불이 붙지 않는다.
    var unlockedGoalTitles: [String] = []

    /// 지금 보상을 받을 수 있으면 불빛이 천천히 밝아졌다 어두워진다.
    @State private var isPulsing = false

    private static let lanternWidth: CGFloat = 130
    private static let lanternHeight: CGFloat = 230
    private static let markRowHeight: CGFloat = 19
    private static let markColumnWidth: CGFloat = 176

    private var isPixel: Bool { PopoverChrome.isGamePixel }
    private var balance: Int { progress.balance }
    private var fillRatio: Double { progress.fillRatio }

    /// 월간 목표를 달성해 불을 붙일 수 있는 상태.
    private var isLit: Bool { !unlockedGoalTitles.isEmpty }
    /// 불도 붙었고 기름도 충분해 실제로 받을 수 있는 상태.
    private var canRedeemNow: Bool { isLit && progress.hasAffordableReward }

    /// 금속 부분 색. 놋쇠 느낌이 나도록 강조색을 어둡게 깔고 테마를 따라간다.
    private var metalColor: Color { PopoverChrome.inkSecondary }

    private var glassTopY: CGFloat { Self.lanternHeight * LanternMetrics.fontTop }
    private var glassHeight: CGFloat { Self.lanternHeight * LanternMetrics.fontHeightRatio }
    private var glassBottomY: CGFloat { glassTopY + glassHeight }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 4) {
                lantern
                    .frame(width: Self.lanternWidth, height: Self.lanternHeight)
                    .accessibilityLabel("모은 포인트 \(balance)")
                markColumn
                    .frame(width: Self.markColumnWidth, height: Self.lanternHeight, alignment: .topLeading)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(PopoverChrome.accent)
                        .frame(width: 7, height: 7)
                    Text("\(balance) P")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .contentTransition(.numericText())
                }

                statusLines
            }
        }
        .animation(.easeOut(duration: 0.45), value: fillRatio)
        .animation(.easeOut(duration: 0.45), value: balance)
        .animation(.easeOut(duration: 0.5), value: isLit)
        .onAppear { syncPulse() }
        .onChange(of: canRedeemNow) { _, _ in syncPulse() }
    }

    private func syncPulse() {
        guard canRedeemNow, !isPixel else {
            isPulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    // MARK: - 상태 문구

    /// 몇 번 받을 수 있는지 먼저 말하고, 어떤 목표 덕분인지는 불씨 칩으로 보여준다.
    ///
    /// 목표 이름을 쉼표로 이어 붙이면 개수가 문장에 묻혀 몇 번 받을 수 있는지 읽히지 않는다.
    /// 칩 하나가 기회 하나라 세어보지 않아도 보이고, 하나 쓰면 칩이 하나 사라진다.
    @ViewBuilder
    private var statusLines: some View {
        if isLit {
            Text("보상을 \(unlockedGoalTitles.count)번 받을 수 있어요")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .transition(.scale.combined(with: .opacity))

            ChanceChipRow(titles: unlockedGoalTitles)
                .transition(.scale.combined(with: .opacity))
        }

        Text(captionText)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .multilineTextAlignment(.center)
    }

    private var captionText: String {
        guard !progress.marks.isEmpty else {
            return "보상 목록에 받고 싶은 걸 먼저 정해보세요"
        }

        // 불이 꺼져 있으면 포인트가 얼마든 그게 가장 중요한 소식이다.
        guard isLit else {
            if progress.hasAffordableReward {
                return "월간 목표를 달성하면 불을 밝힐 수 있어요"
            }
            return progress.pointsToNext.map { "다음 보상까지 \($0)P" }
                ?? "월간 목표를 달성하면 불을 밝힐 수 있어요"
        }

        guard let pointsToNext = progress.pointsToNext else {
            return "목록의 보상을 모두 받을 수 있어요"
        }
        // 이미 받을 수 있는 게 있는데 "더 모으면 받을 수 있어요" 라고 하면
        // 지금 받을 수 있는 보상을 없는 셈 치게 된다.
        return progress.hasAffordableReward
            ? "다음 보상까지 \(pointsToNext)P"
            : "\(pointsToNext)P 더 모으면 받을 수 있어요"
    }

    // MARK: - 랜턴 그리기

    /// 모든 조각을 랜턴 프레임 좌표 그대로 얹는다.
    ///
    /// `offset` 을 준 뷰에 `clipShape` 을 걸면 클립 경로가 그 뷰의 로컬 좌표로 해석돼
    /// 기름이 유리구 밖에 사각형으로 칠해진다. 그래서 좌표계를 하나로 고정한다.
    private var lantern: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if !isPixel, isLit {
                Ellipse()
                    .fill(PopoverChrome.accent.opacity(0.26 * (0.4 + 0.6 * fillRatio)))
                    .frame(width: Self.lanternWidth * 0.8, height: Self.lanternHeight * 0.34)
                    .blur(radius: 18)
                    .scaleEffect(isPulsing ? 1.25 : 1)
                    .offset(x: Self.lanternWidth * 0.1, y: -Self.lanternHeight * 0.06)
            }

            LanternMetalShape()
                .fill(metalColor)

            glass

            flame
        }
        .frame(width: Self.lanternWidth, height: Self.lanternHeight, alignment: .topLeading)
    }

    private var glassRect: CGRect {
        CGRect(x: 0, y: glassTopY, width: Self.lanternWidth, height: glassHeight)
    }

    /// 유리구. 기름이 아래에서 차오르고 그 위로 불꽃이 선다.
    private var glass: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            LanternGlassShape()
                .path(in: glassRect)
                .fill(PopoverChrome.surfaceAlt)

            // 기름과 눈금선은 유리 모양으로 함께 잘라낸다.
            ZStack(alignment: .topLeading) {
                Color.clear

                Rectangle()
                    .fill(oilGradient)
                    .frame(width: Self.lanternWidth, height: glassHeight * fillRatio)
                    .overlay(alignment: .top) {
                        // 기름 표면. 수위를 눈에 띄게 한다.
                        Rectangle()
                            .fill(Color.white.opacity(isPixel ? 0.45 : 0.55))
                            .frame(height: isPixel ? 2 : 1.5)
                    }
                    .offset(y: glassBottomY - glassHeight * fillRatio)

                ForEach(progress.marks) { mark in
                    Rectangle()
                        .fill(mark.isReached ? Color.white.opacity(0.55) : PopoverChrome.divider)
                        .frame(width: Self.lanternWidth, height: 1)
                        .offset(y: glassBottomY - glassHeight * mark.heightRatio)
                }
            }
            .frame(width: Self.lanternWidth, height: Self.lanternHeight, alignment: .topLeading)
            .clipShape(LanternGlassShape().path(in: glassRect))

            LanternGlassShape()
                .path(in: glassRect)
                .stroke(metalColor.opacity(0.45), lineWidth: 1.4)
        }
        .frame(width: Self.lanternWidth, height: Self.lanternHeight, alignment: .topLeading)
    }

    private var oilGradient: AnyShapeStyle {
        if isPixel {
            return AnyShapeStyle(PopoverChrome.accent)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [PopoverChrome.accent.opacity(0.72), PopoverChrome.accent],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// 심지와 불꽃.
    ///
    /// **불은 월간 목표를 달성해야 붙는다.** 기름이 가득해도 불이 꺼져 있으면
    /// 아직 받을 수 없다는 뜻이고, 설명 없이도 그게 보인다.
    private var flame: some View {
        let intensity = 0.35 + 0.65 * fillRatio
        let flameHeight = 26 + 10 * intensity
        let wickBottom = Self.lanternHeight * LanternMetrics.burnerTop

        return VStack(spacing: 0) {
            if isLit {
                FlameShape()
                    .fill(PopoverChrome.accent.opacity(0.75 + 0.25 * intensity))
                    .frame(width: 15 + 6 * intensity, height: flameHeight)
                    .overlay(alignment: .bottom) {
                        FlameShape()
                            .fill(Color.white.opacity(isPixel ? 0.5 : 0.55 + 0.35 * intensity))
                            .frame(width: 6 + 2 * intensity, height: 12 + 5 * intensity)
                            .offset(y: -3)
                    }
                    .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
            }
            // 심지는 불이 꺼져 있어도 남는다.
            Capsule()
                .fill(isLit ? metalColor : metalColor.opacity(0.5))
                .frame(width: 3.5, height: isLit ? 7 : 13)
        }
        .frame(width: Self.lanternWidth, alignment: .center)
        .offset(y: wickBottom - (isLit ? 7 : 13) - (isLit ? flameHeight : 0))
    }

    // MARK: - 눈금

    /// 눈금 라벨이 겹치지 않도록 아래에서 위로 훑으며 최소 간격을 확보한다.
    ///
    /// 48P·50P 처럼 가격이 붙어 있으면 랜턴을 아무리 키워도 라벨이 서로 밟는다.
    /// 선은 실제 높이에 그대로 두고 라벨만 밀어 올린다.
    private func resolvedMarkOffsets() -> [UUID: CGFloat] {
        var offsets: [UUID: CGFloat] = [:]
        var previousY = CGFloat.greatestFiniteMagnitude

        for mark in progress.marks {
            let ideal = glassBottomY - glassHeight * mark.heightRatio - Self.markRowHeight / 2
            let y = min(ideal, previousY - Self.markRowHeight)
            offsets[mark.id] = y
            previousY = y
        }
        return offsets
    }

    /// 랜턴 오른쪽에 보상마다 눈금을 세운다. 기름이 넘어선 눈금은 진하게.
    private var markColumn: some View {
        let offsets = resolvedMarkOffsets()

        return ZStack(alignment: .topLeading) {
            // 눈금자 몸통. 유리구와 같은 구간을 차지해 눈금들이 허공에 뜨지 않게 한다.
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(PopoverChrome.divider)
                    .frame(width: 2, height: glassHeight)
                Capsule()
                    .fill(PopoverChrome.accent)
                    .frame(width: 2, height: glassHeight * fillRatio)
            }
            .offset(x: 3, y: glassTopY)

            ForEach(progress.marks) { mark in
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(mark.isReached ? PopoverChrome.accent : PopoverChrome.divider)
                        .frame(width: 9, height: mark.isReached ? 2 : 1)
                    Text(mark.emoji)
                        .font(.system(size: 11))
                    Text("\(mark.costPoints)P")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(mark.title)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    if mark.isReached {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(mark.isReached ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .frame(height: Self.markRowHeight, alignment: .leading)
                .offset(y: offsets[mark.id] ?? 0)
                .help("\(mark.title) · \(mark.costPoints)P")
            }
        }
        .animation(.easeOut(duration: 0.45), value: fillRatio)
    }
}

/// 달성한 월간 목표를 불씨 칩으로 늘어놓는다. 칩 하나가 보상 한 번을 받을 기회다.
private struct ChanceChipRow: View {
    let titles: [String]

    var body: some View {
        // 이름이 길고 개수도 들쭉날쭉하므로 폭에 맞춰 자동으로 줄바꿈한다.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96, maximum: 190), spacing: 6)],
            alignment: .center,
            spacing: 6
        ) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(PopoverChrome.accentInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PopoverChrome.accent, in: Capsule())
                .help(title)
            }
        }
        .frame(maxWidth: 400)
    }
}
