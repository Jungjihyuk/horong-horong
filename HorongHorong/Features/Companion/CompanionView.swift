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
    /// 브리핑처럼 일정을 보여줄 때. 채팅과 같은 타임라인 카드로 그린다.
    var schedule: [CompanionScheduleEntry] = []
    /// true 면 저절로 사라지지 않고 닫기 버튼이 붙는다.
    var isDismissible: Bool = false
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
    /// 일정 질문에 대한 답이면 저장된 데이터를 그대로 담는다.
    /// 모델이 만든 문장이 아니라 이 값으로 타임라인을 그린다.
    var schedule: [CompanionScheduleEntry] = []
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
    var onDismissBubble: @MainActor () -> Void = {}
    var onShowSchedule: @MainActor () -> Void = {}
    var onRequestMenu: @MainActor () -> Void = {}
    var onDismissMenu: @MainActor () -> Void = {}
    var onAdvanceOnboarding: @MainActor () -> Void = {}
    var onFinishOnboarding: @MainActor () -> Void = {}
    var onStartOnboarding: @MainActor () -> Void = {}

    /// 캐릭터를 오른쪽 클릭했을 때 뜨는 자체 메뉴.
    @Published var isMenuVisible = false
    /// 커서가 캐릭터 위에 있는지. 이 동안에는 걸음을 멈춘다.
    @Published var isHovering = false

    init(character: CompanionCharacter) {
        self.character = character
    }
}

struct CompanionView: View {
    @ObservedObject var state: CompanionPresentationState
    @State private var isDragging = false
    @State private var maxDragDistance: CGFloat = 0

    /// 대화·메뉴·일정 카드처럼 위쪽 공간이 필요할 때는 창이 늘어난다.
    /// 창 크기(`CompanionOverlayPanel`)와 반드시 같은 조건을 써야 내용이 잘리지 않는다.
    private var overlaySize: CGSize {
        let needsRoom = state.isChatting
            || state.isMenuVisible
            || !(state.bubble?.schedule.isEmpty ?? true)
        return needsRoom ? Constants.companionChatOverlaySize : Constants.companionOverlaySize
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            if state.isMenuVisible {
                CompanionMenuCard(state: state)
            } else if state.isChatting {
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
                    .brightness(state.isHovering ? 0.10 : 0)
                    .scaleEffect(state.isHovering ? 1.06 : 1)
                    .shadow(
                        color: .accentColor.opacity(state.isHovering ? 0.55 : 0),
                        radius: state.isHovering ? 9 : 0
                    )
                    .animation(.easeOut(duration: 0.12), value: state.isHovering)
            }
        }
        .frame(
            width: Constants.companionSpriteSize.width,
            height: Constants.companionSpriteSize.height
        )
        // 투명 여백까지 클릭을 가로채지 않도록, 실제로 그려진 부분만 판정 영역으로 쓴다.
        .contentShape(SpriteMaskShape(mask: hitMask))
        .onHover { hovering in
            guard state.isHovering != hovering else { return }
            state.isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(dragGesture)
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
            if bubble.headline != nil || bubble.isDismissible {
                HStack(spacing: 6) {
                    if let headline = bubble.headline {
                        Text(headline)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if bubble.isDismissible {
                        Button {
                            state.onDismissBubble()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("닫기")
                    }
                }
            }

            Text(bubble.message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !bubble.schedule.isEmpty {
                CompanionScheduleCard(entries: bubble.schedule)
            } else if !bubble.detailLines.isEmpty {
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
        .frame(maxWidth: overlaySize.width - 16, alignment: .leading)
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
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 32) }

            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(bubbleBackground(for: message.role))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.schedule.isEmpty {
                    CompanionScheduleCard(entries: message.schedule)
                }
            }

            if message.role == .companion { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private func bubbleBackground(for role: CompanionChatMessage.Role) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 13,
            bottomLeadingRadius: role == .user ? 13 : 4,
            bottomTrailingRadius: role == .user ? 4 : 13,
            topTrailingRadius: 13,
            style: .continuous
        )
        if role == .user {
            shape.fill(Color.accentColor)
        } else {
            shape.fill(Color.primary.opacity(0.07))
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

/// 일정 답변에 붙는 타임라인 카드.
/// 모델이 만든 문장이 아니라 저장된 데이터를 그대로 그린다.
struct CompanionScheduleCard: View {
    let entries: [CompanionScheduleEntry]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("오늘 일정")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, isFirst: index == 0, isLast: index == entries.count - 1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func row(_ entry: CompanionScheduleEntry, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.time.map { Self.timeFormatter.string(from: $0) } ?? "––:––")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(entry.isCompleted ? .tertiary : .secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.top, 1)

            // 점과 이어지는 세로선으로 타임라인을 만든다.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(isFirst ? 0 : 0.12))
                    .frame(width: 1, height: 4)
                Circle()
                    .fill(entry.isCompleted ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(Color.primary.opacity(isLast ? 0 : 0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 6)

            Text(entry.title)
                .font(.system(size: 11.5))
                .foregroundStyle(entry.isCompleted ? .secondary : .primary)
                .strikethrough(entry.isCompleted, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, isLast ? 0 : 9)
        }
    }
}


/// 캐릭터를 오른쪽 클릭했을 때 나오는 메뉴.
/// 시스템 메뉴 대신 말풍선과 같은 결로 그려 캐릭터와 톤을 맞춘다.
private struct CompanionMenuCard: View {
    @ObservedObject var state: CompanionPresentationState
    @State private var hovered: String?

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        var isDestructive: Bool = false
        let action: @MainActor () -> Void
    }

    /// 성격이 다른 항목을 구분선으로 나눈다.
    /// 지금 할 일 / 배우기 / 끄기 — 재우기는 파괴적 동작이라 맨 아래에 둔다.
    private var sections: [[Item]] {
        [
            [
                Item(id: "schedule", icon: "list.bullet.rectangle", title: "오늘 일정 보기") {
                    state.onDismissMenu()
                    state.onShowSchedule()
                },
                Item(id: "chat", icon: "bubble.left.and.bubble.right", title: state.isChatting ? "대화 닫기" : "말 걸기") {
                    state.onDismissMenu()
                    state.onCharacterTap()
                },
            ],
            [
                Item(id: "guide", icon: "questionmark.circle", title: "사용법 안내") {
                    state.onDismissMenu()
                    state.onStartOnboarding()
                },
            ],
            [
                Item(id: "off", icon: "moon.zzz", title: "재우기", isDestructive: true) {
                    state.onDismissMenu()
                    state.onTurnOff()
                },
            ],
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(state.character.displayName)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    state.onDismissMenu()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ForEach(Array(sections.enumerated()), id: \.offset) { index, items in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                ForEach(items) { item in
                    row(item)
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 168)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 3)
        .onDisappear { hovered = nil }
    }

    private func row(_ item: Item) -> some View {
        let isHovered = hovered == item.id
        return Button(action: item.action) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(item.isDestructive ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.primary))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovered = $0 ? item.id : nil }
    }
}
