import SwiftUI

/// 보상을 받는 순간의 개봉 연출.
///
/// 상자가 들썩이다 뚜껑이 열리고 빛이 퍼지면서 받은 보상이 나온다.
/// 포인트가 깎이는 것도 여기서 함께 보여준다.
struct RewardUnboxingOverlay: View {
    let emoji: String
    let title: String
    let costPoints: Int
    let remainingBalance: Int
    let onDismiss: () -> Void

    private enum Phase {
        /// 닫힌 상자가 들썩인다.
        case shaking
        /// 뚜껑이 열리고 빛이 터진다.
        case opening
        /// 받은 보상이 드러난다.
        case revealed
    }

    @State private var phase: Phase = .shaking
    @State private var wobble: Double = 0
    @State private var lidLift: CGFloat = 0
    @State private var burst: Double = 0
    @State private var rewardScale: CGFloat = 0.2
    @State private var rewardOpacity: Double = 0

    private var isPixel: Bool { PopoverChrome.isGamePixel }

    var body: some View {
        VStack(spacing: 18) {
            // 빛줄기는 상자·보상 뒤에만 둔다. 제목까지 감싸면 글자와 겹쳐 읽기 힘들다.
            ZStack {
                if phase != .shaking {
                    rays
                }
                if phase == .revealed {
                    Text(emoji)
                        .font(.system(size: 58))
                        .scaleEffect(rewardScale)
                        .opacity(rewardOpacity)
                } else {
                    giftBox
                }
            }
            .frame(width: 190, height: 152)

            if phase == .revealed {
                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.ink)
                        .multilineTextAlignment(.center)
                    resultText
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("보상을 여는 중…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
        }
        .frame(width: 320)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(PopoverChrome.surface)
        .appearanceAccentTint(.popover)
        .task { await runSequence() }
    }

    // MARK: - 연출 순서

    private func runSequence() async {
        // 1. 상자가 세 번 들썩인다.
        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.11)) { wobble = 7 }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeInOut(duration: 0.11)) { wobble = -7 }
            try? await Task.sleep(for: .milliseconds(110))
        }
        withAnimation(.easeInOut(duration: 0.09)) { wobble = 0 }
        try? await Task.sleep(for: .milliseconds(90))

        // 2. 뚜껑이 튀어 오르고 빛이 퍼진다.
        phase = .opening
        withAnimation(.easeOut(duration: 0.28)) {
            lidLift = -54
            burst = 1
        }
        try? await Task.sleep(for: .milliseconds(240))

        // 3. 보상이 드러난다.
        phase = .revealed
        withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) {
            rewardScale = 1
            rewardOpacity = 1
        }
    }

    // MARK: - 조각

    /// 열릴 때 뒤에서 퍼지는 빛줄기.
    private var rays: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(PopoverChrome.accent.opacity(0.5))
                    .frame(width: 4, height: 30 + (index.isMultiple(of: 2) ? 14 : 0))
                    .offset(y: -52)
                    .rotationEffect(.degrees(Double(index) / 12 * 360))
            }
            .scaleEffect(0.5 + 0.9 * burst)
            .opacity(burst * (phase == .revealed ? 0.55 : 1))

            if !isPixel {
                Circle()
                    .fill(PopoverChrome.accent.opacity(0.28 * burst))
                    .frame(width: 130, height: 130)
                    .blur(radius: 22)
            }
        }
    }

    private var giftBox: some View {
        VStack(spacing: 0) {
            // 뚜껑
            ZStack {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(6), style: .continuous)
                    .fill(PopoverChrome.accent)
                    .frame(width: 104, height: 26)
                Rectangle()
                    .fill(PopoverChrome.accentInk.opacity(0.75))
                    .frame(width: 14, height: 26)
            }
            .offset(y: lidLift)
            .rotationEffect(.degrees(lidLift == 0 ? 0 : -12), anchor: .bottomLeading)

            // 몸통
            ZStack {
                RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous)
                    .fill(PopoverChrome.accent.opacity(0.82))
                    .frame(width: 92, height: 70)
                Rectangle()
                    .fill(PopoverChrome.accentInk.opacity(0.75))
                    .frame(width: 14, height: 70)
            }
        }
        .rotationEffect(.degrees(wobble), anchor: .bottom)
    }

    private var resultText: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("−\(costPoints) P")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Text("남은 포인트 \(remainingBalance) P")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accent)
            }

            Button("보관함에 넣기") { onDismiss() }
                .buttonStyle(LanternPrimaryButtonStyle())
        }
    }
}
