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
    let balance: Int
    /// 다음 보상까지 남은 포인트. 다 살 수 있거나 목록이 비면 nil.
    let pointsToNext: Int?
    /// 0…1. `RewardLedger.fillRatio` 로 구한 값.
    let fillRatio: Double

    private var isPixel: Bool { PopoverChrome.isGamePixel }

    var body: some View {
        VStack(spacing: 14) {
            lantern
                .frame(width: 108, height: 132)
                .accessibilityLabel("모은 포인트 \(balance)")

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(PopoverChrome.accent)
                        .frame(width: 7, height: 7)
                    Text("\(balance) P")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .contentTransition(.numericText())
                }

                Text(captionText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
        }
        .animation(.easeOut(duration: 0.45), value: fillRatio)
        .animation(.easeOut(duration: 0.45), value: balance)
    }

    private var captionText: String {
        guard let pointsToNext else {
            return balance > 0 ? "고를 수 있는 보상이 있어요" : "주간 목표를 달성하면 기름이 차올라요"
        }
        return "다음 보상까지 \(pointsToNext)P"
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

    /// 심지 위의 불꽃. 기름이 많을수록 크고 밝다.
    private var flame: some View {
        let intensity = 0.35 + 0.65 * fillRatio

        return ZStack(alignment: .bottom) {
            if !isPixel {
                Circle()
                    .fill(PopoverChrome.accent.opacity(0.30 * intensity))
                    .frame(width: 44, height: 44)
                    .blur(radius: 11)
            }

            VStack(spacing: 0) {
                FlameShape()
                    .fill(PopoverChrome.accent.opacity(0.55 + 0.45 * intensity))
                    .frame(width: 12 + 5 * intensity, height: 20 + 8 * intensity)
                    .overlay(alignment: .bottom) {
                        FlameShape()
                            .fill(Color.white.opacity(isPixel ? 0.45 : 0.6 * intensity))
                            .frame(width: 5 + 2 * intensity, height: 9 + 4 * intensity)
                            .offset(y: -2)
                    }
                // 심지
                Capsule()
                    .fill(PopoverChrome.inkTertiary)
                    .frame(width: 2.5, height: 6)
            }
        }
        .opacity(balance > 0 ? 1 : 0.25)
    }
}
