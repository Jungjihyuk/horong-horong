import SwiftUI

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

/// 호롱 몸통 실루엣. 위쪽 좁은 목에서 어깨를 지나 둥근 기름통으로 벌어진다.
private struct LanternJarShape: Shape {
    /// 목이 끝나고 몸통이 시작되는 높이 비율. 기름은 이 아래로만 찬다.
    static let neckRatio: CGFloat = 0.20


    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let neckWidth = w * 0.34
        let neckBottom = h * Self.neckRatio
        let shoulder = h * 0.34
        let waist = h * 0.46

        var path = Path()
        path.move(to: CGPoint(x: (w - neckWidth) / 2, y: 0))
        path.addLine(to: CGPoint(x: (w + neckWidth) / 2, y: 0))
        path.addLine(to: CGPoint(x: (w + neckWidth) / 2, y: neckBottom))
        // 오른쪽 어깨 → 배 → 바닥
        path.addQuadCurve(
            to: CGPoint(x: w, y: waist),
            control: CGPoint(x: w * 0.94, y: shoulder)
        )
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: h),
            control: CGPoint(x: w, y: h)
        )
        // 왼쪽 바닥 → 배 → 어깨
        path.addQuadCurve(
            to: CGPoint(x: 0, y: waist),
            control: CGPoint(x: 0, y: h)
        )
        path.addQuadCurve(
            to: CGPoint(x: (w - neckWidth) / 2, y: neckBottom),
            control: CGPoint(x: w * 0.06, y: shoulder)
        )
        path.closeSubpath()
        return path
    }
}

/// 모은 포인트를 호롱불의 기름으로 보여준다.
/// 기름이 차오를수록 심지 불빛이 밝아진다.
struct LanternOilJarView: View {
    let progress: RewardProgress
    /// 달성했지만 아직 보상을 안 고른 월간 목표 이름들.
    /// 기름(포인트)이 아무리 차도 이게 비어 있으면 불이 붙지 않는다.
    var unlockedGoalTitles: [String] = []

    /// 지금 보상을 받을 수 있으면 불빛이 천천히 밝아졌다 어두워진다.
    @State private var isPulsing = false

    private var isPixel: Bool { PopoverChrome.isGamePixel }
    private var balance: Int { progress.balance }
    private var fillRatio: Double { progress.fillRatio }

    /// 월간 목표를 달성해 불을 붙일 수 있는 상태.
    private var isLit: Bool { !unlockedGoalTitles.isEmpty }
    /// 불도 붙었고 기름도 충분해 실제로 받을 수 있는 상태.
    private var canRedeemNow: Bool { isLit && progress.hasAffordableReward }

    var body: some View {
        VStack(spacing: 14) {
            lantern
                .frame(width: 108, height: 132)
                .accessibilityLabel("모은 포인트 \(balance)")

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

    /// 불이 붙었으면 어떤 목표 덕분인지 먼저 말하고, 그다음 지금 받을 수 있는지 말한다.
    @ViewBuilder
    private var statusLines: some View {
        if isLit {
            Text("🎉 «\(unlockedGoalTitles.joined(separator: "», «"))» 달성!")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.accent)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .transition(.scale.combined(with: .opacity))
        }

        Text(captionText)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .multilineTextAlignment(.center)
    }

    private var captionText: String {
        guard progress.pointsToNext != nil || progress.hasAffordableReward else {
            return "보상 목록에 받고 싶은 걸 먼저 정해보세요"
        }
        if let pointsToNext = progress.pointsToNext {
            return isLit
                ? "\(pointsToNext)P 더 모으면 받을 수 있어요"
                : "다음 보상까지 \(pointsToNext)P"
        }
        // 기름은 가득 찼다. 불만 붙이면 된다.
        return isLit
            ? "지금 보상을 받을 수 있어요"
            : "월간 목표를 달성하면 불을 밝힐 수 있어요"
    }

    // MARK: - 호롱

    private var lantern: some View {
        VStack(spacing: -3) {
            flame
                .frame(height: 32)
            jar
        }
    }

    private var jar: some View {
        LanternJarShape()
            .fill(PopoverChrome.surfaceAlt)
            .overlay {
                // 기름은 몸통(목 아래)에서만 차오른다.
                // 전체 높이를 기준으로 잡으면 절반만 차도 몸통이 가득 차 보여 수위를 읽을 수 없다.
                GeometryReader { proxy in
                    let bodyHeight = proxy.size.height * (1 - LanternJarShape.neckRatio)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        oilFill
                            .frame(height: bodyHeight * fillRatio)
                            .overlay(alignment: .top) {
                                // 기름 표면. 수위를 눈에 띄게 한다.
                                Rectangle()
                                    .fill(Color.white.opacity(isPixel ? 0.45 : 0.55))
                                    .frame(height: isPixel ? 2 : 1.5)
                            }
                    }
                }
                .clipShape(LanternJarShape())
            }
            .overlay {
                LanternJarShape()
                    .stroke(PopoverChrome.divider, lineWidth: isPixel ? 2 : 1)
            }
    }

    @ViewBuilder
    private var oilFill: some View {
        if isPixel {
            // 픽셀 테마는 그라데이션 없이 단색으로 각지게.
            Rectangle().fill(PopoverChrome.accent)
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [PopoverChrome.accent.opacity(0.75), PopoverChrome.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    /// 심지와 불꽃.
    ///
    /// **불은 월간 목표를 달성해야 붙는다.** 기름(포인트)이 가득해도 불이 꺼져 있으면
    /// 아직 받을 수 없다는 뜻이고, 설명 없이도 그게 보인다.
    /// 불이 붙은 뒤의 크기·밝기는 기름 양을 따른다.
    private var flame: some View {
        let intensity = 0.35 + 0.65 * fillRatio

        return ZStack(alignment: .bottom) {
            if !isPixel, isLit {
                Circle()
                    .fill(PopoverChrome.accent.opacity(0.30 * intensity))
                    .frame(width: 44, height: 44)
                    .blur(radius: 11)
                    .scaleEffect(isPulsing ? 1.35 : 1)
                    .opacity(isPulsing ? 1 : 0.75)
            }

            VStack(spacing: 0) {
                if isLit {
                    FlameShape()
                        .fill(PopoverChrome.accent.opacity(0.55 + 0.45 * intensity))
                        .frame(width: 12 + 5 * intensity, height: 20 + 8 * intensity)
                        .overlay(alignment: .bottom) {
                            FlameShape()
                                .fill(Color.white.opacity(isPixel ? 0.45 : 0.6 * intensity))
                                .frame(width: 5 + 2 * intensity, height: 9 + 4 * intensity)
                                .offset(y: -2)
                        }
                        .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                }
                // 심지는 불이 꺼져 있어도 남는다.
                Capsule()
                    .fill(isLit ? PopoverChrome.inkTertiary : PopoverChrome.inkTertiary.opacity(0.55))
                    .frame(width: 2.5, height: isLit ? 6 : 9)
            }
        }
    }
}
