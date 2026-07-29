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

struct CompanionChatMessage: Identifiable {
    enum Role {
        case user
        case companion
    }

    let id = UUID()
    let role: Role
    var text: String
}

/// 오버레이 창이 그리는 내용. 컨트롤러가 값을 밀어 넣고 뷰는 표시·입력 전달만 한다.
@MainActor
final class CompanionPresentationState: ObservableObject {
    @Published var character: CompanionCharacter
    @Published var animation: CompanionAnimation = .idle
    @Published var frameIndex: Int = 0
    @Published var bubble: CompanionBubble?

    @Published var isChatting = false
    @Published var chatMessages: [CompanionChatMessage] = []
    @Published var isAwaitingReply = false

    /// 뷰 → 컨트롤러 방향의 사용자 조작.
    var onCharacterTap: @MainActor () -> Void = {}
    var onSendMessage: @MainActor (String) -> Void = { _ in }
    var onCloseChat: @MainActor () -> Void = {}
    var onDragBegan: @MainActor () -> Void = {}
    var onDragChanged: @MainActor () -> Void = {}
    var onDragEnded: @MainActor () -> Void = {}
    var onTurnOff: @MainActor () -> Void = {}

    init(character: CompanionCharacter) {
        self.character = character
    }
}

struct CompanionView: View {
    @ObservedObject var state: CompanionPresentationState
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var maxDragDistance: CGFloat = 0

    private var overlaySize: CGSize {
        state.isChatting ? Constants.companionChatOverlaySize : Constants.companionOverlaySize
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            if state.isChatting {
                CompanionChatPanel(state: state)
            } else if let bubble = state.bubble {
                bubbleView(bubble)
            }

            sprite
        }
        .frame(width: overlaySize.width, height: overlaySize.height, alignment: .bottom)
        // 배경을 두지 않아 투명한 영역의 클릭은 아래 창으로 그대로 통과한다.
        // (캐릭터와 말풍선·대화창만 마우스를 받는다.)
    }

    @ViewBuilder
    private var sprite: some View {
        let frames = CompanionSpriteLoader.shared.frames(
            for: state.character,
            animation: state.animation
        )
        let hitMask = CompanionSpriteLoader.shared.hitMask(
            for: state.character,
            animation: state.animation
        )

        Group {
            if frames.isEmpty {
                // 스프라이트를 못 찾아도 창이 사라지지 않도록 자리만 유지한다.
                Color.clear
            } else {
                Image(nsImage: frames[min(state.frameIndex, frames.count - 1)])
                    .resizable()
                    .interpolation(.high)
                    .brightness(isHovering ? 0.10 : 0)
                    .scaleEffect(isHovering ? 1.06 : 1)
                    .shadow(
                        color: .accentColor.opacity(isHovering ? 0.55 : 0),
                        radius: isHovering ? 9 : 0
                    )
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
        }
        .frame(
            width: Constants.companionSpriteSize.width,
            height: Constants.companionSpriteSize.height
        )
        // 투명 여백까지 클릭을 가로채지 않도록, 실제로 그려진 부분만 판정 영역으로 쓴다.
        .contentShape(SpriteMaskShape(mask: hitMask))
        .onHover { hovering in
            guard isHovering != hovering else { return }
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(dragGesture)
        .contextMenu {
            Button(state.isChatting ? "대화 닫기" : "대화하기") {
                state.onCharacterTap()
            }
            Divider()
            Button("루미롱 끄기") { state.onTurnOff() }
        }
        .help(state.isChatting ? "대화 중 · 끌어서 옮기기" : "눌러서 말 걸기 · 끌어서 옮기기")
    }

    /// 탭과 드래그를 한 제스처에서 구분한다.
    /// 창이 커서를 따라 움직이면 translation 이 0 근처로 되돌아오므로 최대 이동량으로 판정한다.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                maxDragDistance = max(maxDragDistance, distance)
                if !isDragging, maxDragDistance > 4 {
                    isDragging = true
                    state.onDragBegan()
                }
                if isDragging {
                    state.onDragChanged()
                }
            }
            .onEnded { _ in
                if isDragging {
                    state.onDragEnded()
                } else {
                    state.onCharacterTap()
                }
                isDragging = false
                maxDragDistance = 0
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

/// 격자 마스크를 실제 크기의 도형으로 환산한다. 스프라이트 클릭 영역에 쓴다.
private struct SpriteMaskShape: Shape {
    let mask: CompanionSpriteMask

    func path(in rect: CGRect) -> Path {
        guard mask.columns > 0, mask.rows > 0 else { return Path(rect) }
        let cellWidth = rect.width / CGFloat(mask.columns)
        let cellHeight = rect.height / CGFloat(mask.rows)

        var path = Path()
        for row in 0..<mask.rows {
            // 같은 행에서 이어지는 칸은 한 사각형으로 합쳐 도형을 단순하게 유지한다.
            var runStart: Int?
            for column in 0...mask.columns {
                let isFilled = column < mask.columns && mask.isFilled(column: column, row: row)
                switch (isFilled, runStart) {
                case (true, nil):
                    runStart = column
                case (false, let start?):
                    path.addRect(
                        CGRect(
                            x: rect.minX + CGFloat(start) * cellWidth,
                            y: rect.minY + CGFloat(row) * cellHeight,
                            width: CGFloat(column - start) * cellWidth,
                            height: cellHeight
                        )
                    )
                    runStart = nil
                default:
                    break
                }
            }
        }
        return path.isEmpty ? Path(rect) : path
    }
}

/// 캐릭터 위로 펼쳐지는 대화창.
private struct CompanionChatPanel: View {
    @ObservedObject var state: CompanionPresentationState
    @State private var draft: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(
            width: Constants.companionChatOverlaySize.width - 16,
            height: Constants.companionChatOverlaySize.height
                - Constants.companionSpriteSize.height - 18
        )
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 2)
        .onAppear { isInputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(state.character.displayName)
                .font(.system(size: 12, weight: .bold))
            Spacer(minLength: 0)
            Button {
                state.onCloseChat()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("대화 닫기 (esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.chatMessages) { message in
                        messageRow(message).id(message.id)
                    }
                    if state.isAwaitingReply {
                        Text("…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("typing")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: state.chatMessages.count) { _, _ in
                if let last = state.chatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func messageRow(_ message: CompanionChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(Color.accentColor)
                              : AnyShapeStyle(Color.primary.opacity(0.08)))
                )
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .companion { Spacer(minLength: 24) }
        }
    }

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("무슨 얘기를 할까요?", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isInputFocused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(trimmedDraft.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let message = trimmedDraft
        guard !message.isEmpty else { return }
        draft = ""
        state.onSendMessage(message)
    }
}
