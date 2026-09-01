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
    /// 이 말풍선으로 만든 메모. 값이 있으면 다시 저장할 수 없다.
    var savedMemoID: UUID?
    /// 값이 있으면 메모 저장 완료 말풍선이며 메모 탭으로 가는 버튼을 보여준다.
    var memoDestinationID: UUID?
    var allowsMemoSave = true
    var isHovered = false
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
    @Published var streamingMessageID: UUID?

    /// 뷰 → 컨트롤러 방향의 사용자 조작.
    var onCharacterTap: @MainActor () -> Void = {}
    var onSendMessage: @MainActor (String) -> Void = { _ in }
    var onSaveMessageAsMemo: @MainActor (UUID, String, Bool) -> Void = { _, _, _ in }
    var onOpenMemoTab: @MainActor () -> Void = {}
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
    /// 말풍선을 캐릭터 아래에 그릴지. 화면 위쪽에 붙어 위에 자리가 없을 때 창이 켜준다.
    @Published var isCardBelow = false

    init(character: CompanionCharacter) {
        self.character = character
    }
}

struct CompanionView: View {
    @ObservedObject var state: CompanionPresentationState
    /// 말풍선·대화창·메뉴가 실제로 차지한 자리를 창에 알려준다.
    /// 창은 이 자리와 캐릭터 위에서만 클릭을 받고 나머지는 아래 앱으로 넘긴다.
    var onContentFrameChange: (CGRect) -> Void = { _ in }
    @State private var isDragging = false
    @State private var maxDragDistance: CGFloat = 0
    @AppStorage(Constants.AppStorageKey.companionBubbleSize)
    private var bubbleSizeRaw: String = Constants.defaultCompanionBubbleSize

    private var bubbleSize: Constants.CompanionBubbleSize {
        Constants.CompanionBubbleSize(rawValue: bubbleSizeRaw) ?? .regular
    }

    /// 말풍선이 쓸 수 있는 최대 높이. 이보다 길어지면 잘리지 않고 스크롤된다.
    private var bubbleMaxHeight: CGFloat { bubbleSize.bubbleMaxHeight }

    /// 대화·메뉴·일정 카드처럼 위쪽 공간이 필요할 때는 창이 늘어난다.
    /// 창 크기(`CompanionOverlayPanel`)와 반드시 같은 조건을 써야 내용이 잘리지 않는다.
    private var overlaySize: CGSize {
        let needsRoom = state.isChatting
            || state.isMenuVisible
            || !(state.bubble?.schedule.isEmpty ?? true)
        return needsRoom ? Constants.companionExpandedOverlaySize : Constants.companionOverlaySize
    }

    var body: some View {
        VStack(spacing: 6) {
            // 화면 위쪽에 붙어 말풍선이 올라갈 자리가 없으면 캐릭터 아래에 그린다.
            if state.isCardBelow {
                sprite
                card
                    .background(contentFrameReader)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                card
                    .background(contentFrameReader)
                sprite
            }
        }
        .frame(
            width: overlaySize.width,
            height: overlaySize.height,
            alignment: state.isCardBelow ? .top : .bottom
        )
        .coordinateSpace(.named(Self.overlaySpace))
        .appearanceAccentTint(.adaptive)
        // 배경을 두지 않아 투명한 영역에는 아무것도 그리지 않는다.
        // 다만 macOS 는 투명하다고 클릭을 통과시켜 주지 않으므로,
        // 실제 통과 처리는 창이 맡는다. (`CompanionOverlayPanel`)
    }

    /// 캐릭터 위로 뜨는 카드. 셋 중 하나만 보이고, 없을 때는 자리를 차지하지 않는다.
    @ViewBuilder
    private var card: some View {
        if state.isMenuVisible {
            CompanionMenuCard(state: state)
        } else if state.isChatting {
            CompanionChatPanel(state: state)
        } else if let bubble = state.bubble {
            // 할일이 많으면 말풍선이 창 높이를 넘어 위가 잘렸다. 넘칠 때만 스크롤로 넘긴다.
            // (`.scrollBounceBehavior` 를 꺼서 짧을 때 헛도는 느낌이 없게 한다.)
            ScrollView(.vertical) {
                bubbleView(bubble)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .frame(maxHeight: bubbleMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // 카드가 없을 때도 같은 자리를 계속 보고해야 창이 이전 크기에 머물지 않는다.
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// 카드가 차지한 자리를 창에 알려준다. 창은 이 밖의 투명한 영역에서 클릭을 비켜 준다.
    private var contentFrameReader: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named(Self.overlaySpace))
            Color.clear
                .onAppear { onContentFrameChange(frame) }
                .onChange(of: frame) { _, newFrame in onContentFrameChange(newFrame) }
        }
    }

    /// 카드 위치를 잴 기준. 창 왼쪽 위가 원점이다.
    private static let overlaySpace = "companionOverlay"

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
                // **양쪽을 다 조인다.** `min` 만 두면 음수 프레임 번호가 그대로 통과해
                // 앱이 죽는다(크래시 2026-08-19: 시계가 뒤로 가 프레임 번호가 음수가 됐다).
                // 프레임을 정하는 쪽(`CompanionController`)에서도 막지만, 화면이 죽는 것보다
                // 잠깐 첫 프레임이 보이는 편이 낫다.
                Image(nsImage: frames[min(max(state.frameIndex, 0), frames.count - 1)])
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

            Text(CompanionMarkdown.styled(bubble.message))
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
                    Spacer(minLength: 0)
                    ForEach(bubble.actions) { action in
                        Button(action.title) { action.handler() }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .disabled(!action.isEnabled)
                            .help(action.hint ?? "")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
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
            // 답변은 같은 말풍선의 글자가 늘어나는 방식이라 메시지 개수가 그대로다.
            // 개수만 보면 스트리밍 도중에 따라가지 못하므로 마지막 글자 수도 함께 본다.
            .onChange(of: scrollAnchor) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    /// 스크롤을 다시 내려야 하는지 판단하는 값.
    private var scrollAnchor: String {
        "\(state.chatMessages.count)-\(state.chatMessages.last?.text.count ?? 0)-\(state.isAwaitingReply)"
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = state.chatMessages.last else { return }
        let target = state.isAwaitingReply ? "typing" : last.id.uuidString
        let scroll = {
            if state.isAwaitingReply {
                proxy.scrollTo(target, anchor: .bottom)
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { scroll() }
        } else {
            scroll()
        }
    }

    private func messageRow(_ message: CompanionChatMessage) -> some View {
        CompanionChatMessageRow(
            message: message,
            isStreaming: state.streamingMessageID == message.id,
            onSave: { icon, isTodayTask in
                state.onSaveMessageAsMemo(message.id, icon, isTodayTask)
            },
            onOpenMemoTab: state.onOpenMemoTab
        )
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

private struct CompanionChatMessageRow: View {
    let message: CompanionChatMessage
    let isStreaming: Bool
    let onSave: (String, Bool) -> Void
    let onOpenMemoTab: () -> Void

    @State private var isHovering = false
    @State private var isShowingMemoOptions = false
    @State private var selectedIcon = MemoIcon.defaultIcon
    @State private var isTodayTask = false
    @State private var hoverDismissTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if message.role == .user {
                Spacer(minLength: 32)
                memoActionButton
            }

            messageContent

            if message.role == .companion {
                memoActionButton
                Spacer(minLength: 32)
            }
        }
        // 말풍선과 메모 버튼 사이의 투명한 간격도 같은 hover 영역으로 취급한다.
        .contentShape(Rectangle())
        .onHover(perform: updateHover)
        .onDisappear {
            hoverDismissTask?.cancel()
        }
    }

    @ViewBuilder
    private var memoActionButton: some View {
        if message.allowsMemoSave, !message.text.isEmpty {
            Button {
                guard message.savedMemoID == nil, !isStreaming else { return }
                isShowingMemoOptions = true
            } label: {
                Image(systemName: message.savedMemoID == nil ? "note.text.badge.plus" : "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(message.savedMemoID == nil ? .secondary : Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(message.savedMemoID != nil || isStreaming)
            .opacity(isHovering || isShowingMemoOptions || message.isHovered ? 1 : 0)
            .onHover(perform: updateHover)
            .help(message.savedMemoID == nil ? "메모로 저장" : "이미 메모로 저장됨")
            .popover(isPresented: $isShowingMemoOptions, arrowEdge: .bottom) {
                memoOptions
            }
        }
    }

    private func updateHover(_ isInside: Bool) {
        hoverDismissTask?.cancel()

        if isInside {
            isHovering = true
            return
        }

        // macOS가 말풍선과 인접 버튼 사이에서 짧은 이탈 이벤트를 보내도
        // 버튼에 진입할 시간을 주고, 다시 들어오면 위에서 숨김을 취소한다.
        hoverDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isHovering = false
        }
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(bubbleBackground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !message.schedule.isEmpty {
                CompanionScheduleCard(entries: message.schedule)
            }
            if message.memoDestinationID != nil {
                Button {
                    onOpenMemoTab()
                } label: {
                    Label("기록 탭 보기", systemImage: "arrow.up.right")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 13,
            bottomLeadingRadius: message.role == .user ? 13 : 4,
            bottomTrailingRadius: message.role == .user ? 4 : 13,
            topTrailingRadius: 13,
            style: .continuous
        )
        if message.role == .user {
            shape.fill(Color.accentColor)
        } else {
            shape.fill(Color.primary.opacity(0.07))
        }
    }

    private var memoOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("메모로 저장")
                .font(.system(size: 12, weight: .bold))

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(28), spacing: 5), count: 5),
                spacing: 5
            ) {
                ForEach(MemoIcon.options, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Text(icon)
                            .font(.system(size: 16))
                            .frame(width: 26, height: 26)
                            .background(
                                selectedIcon == icon
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        selectedIcon == icon ? Color.accentColor : .clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(MemoIcon.label(for: icon))
                }
            }

            Toggle("오늘 할 일로 표시", isOn: $isTodayTask)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11.5))

            Button {
                onSave(selectedIcon, isTodayTask)
                isShowingMemoOptions = false
            } label: {
                Text("저장")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 190)
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

            VStack(alignment: .leading, spacing: Self.rowGap) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, isFirst: index == 0, isLast: index == entries.count - 1)
                }
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

    /// 행 사이 간격. 모든 행에 똑같이 준다.
    private static let rowGap: CGFloat = 9
    private static let timeWidth: CGFloat = 36
    private static let dotWidth: CGFloat = 6
    private static let columnSpacing: CGFloat = 8

    /// 행은 시각·제목 한 줄로만 이뤄져 높이가 늘 같다.
    /// 점과 세로선은 레이아웃에 참여하지 않는 겹쳐 그리기라 행 높이를 바꾸지 못한다.
    private func row(_ entry: CompanionScheduleEntry, isFirst: Bool, isLast: Bool) -> some View {
        HStack(spacing: Self.columnSpacing) {
            Text(entry.time.map { Self.timeFormatter.string(from: $0) } ?? "––:––")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(entry.isCompleted ? .tertiary : .secondary)
                .frame(width: Self.timeWidth, alignment: .trailing)

            Text(entry.title)
                .font(.system(size: 11.5))
                .foregroundStyle(entry.isCompleted ? .secondary : .primary)
                .strikethrough(entry.isCompleted, color: .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.dotWidth + Self.columnSpacing)
        }
        .overlay(alignment: .topLeading) {
            connector(entry, isFirst: isFirst, isLast: isLast)
                .padding(.leading, Self.timeWidth + Self.columnSpacing)
        }
    }

    /// 위 꼬리 · 점 · 아래 꼬리로 이어지는 타임라인 선.
    /// 아래 꼬리는 음수 여백으로 행 사이 간격까지 내려가 선이 끊기지 않게 한다.
    private func connector(_ entry: CompanionScheduleEntry, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(isFirst ? 0 : 0.12))
                .frame(width: 1, height: 4)
            Circle()
                .fill(entry.isCompleted ? Color.secondary.opacity(0.4) : Color.accentColor)
                .frame(width: Self.dotWidth, height: Self.dotWidth)
            Rectangle()
                .fill(Color.primary.opacity(isLast ? 0 : 0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: Self.dotWidth)
        .padding(.bottom, -Self.rowGap)
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
                    if state.isChatting {
                        state.onCloseChat()
                    } else {
                        state.onCharacterTap()
                    }
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
        .companionHighlight("companion.menu.\(item.id)")
        .onHover { hovered = $0 ? item.id : nil }
    }
}
