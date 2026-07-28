import AppKit
import SwiftUI

struct CompanionBubbleAction: Identifiable {
    let id = UUID()
    let title: String
    var isEnabled: Bool = true
    var hint: String?
    let handler: @MainActor () -> Void
}

struct CompanionBubble {
    var headline: String?
    var message: String
    var detailLines: [String] = []
    var actions: [CompanionBubbleAction] = []
}

/// 오버레이 창이 그리는 내용. 컨트롤러가 값을 밀어 넣고 뷰는 표시만 한다.
@MainActor
final class CompanionPresentationState: ObservableObject {
    @Published var character: CompanionCharacter
    @Published var animation: CompanionAnimation = .idle
    @Published var frameIndex: Int = 0
    @Published var bubble: CompanionBubble?

    init(character: CompanionCharacter) {
        self.character = character
    }
}

struct CompanionView: View {
    @ObservedObject var state: CompanionPresentationState

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            if let bubble = state.bubble {
                bubbleView(bubble)
            }

            sprite
        }
        .frame(
            width: Constants.companionOverlaySize.width,
            height: Constants.companionOverlaySize.height,
            alignment: .bottom
        )
        // 배경을 두지 않아 투명한 영역의 클릭은 아래 창으로 그대로 통과한다.
        // (말풍선·캐릭터만 마우스를 받는다.)
    }

    @ViewBuilder
    private var sprite: some View {
        let frames = CompanionSpriteLoader.shared.frames(
            for: state.character,
            animation: state.animation
        )
        if frames.isEmpty {
            // 스프라이트를 못 찾아도 창이 사라지지 않도록 자리만 유지한다.
            Color.clear
                .frame(
                    width: Constants.companionSpriteSize.width,
                    height: Constants.companionSpriteSize.height
                )
                .allowsHitTesting(false)
        } else {
            Image(nsImage: frames[min(state.frameIndex, frames.count - 1)])
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Constants.companionSpriteSize.width,
                    height: Constants.companionSpriteSize.height
                )
        }
    }

    private func bubbleView(_ bubble: CompanionBubble) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let headline = bubble.headline {
                Text(headline)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text(bubble.message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !bubble.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bubble.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if !bubble.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(bubble.actions) { action in
                        Button(action.title) { action.handler() }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .disabled(!action.isEnabled)
                            .help(action.hint ?? "")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: Constants.companionOverlaySize.width - 16, alignment: .leading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}
