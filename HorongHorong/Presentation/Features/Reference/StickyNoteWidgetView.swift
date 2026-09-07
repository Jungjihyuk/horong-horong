import SwiftUI

/// 떠 있는 쪽지 위젯의 내용.
///
/// 본 창이 아니라 자기 창 안에 살기 때문에 **자기 상태를 스스로 들고 다시 읽는다.**
/// 본 창에서 같은 쪽지를 고쳤을 때는 `ReferenceChangeBroadcast` 로 알림을 받는다.
struct StickyNoteWidgetView: View {
    let repository: ReferenceRepository
    let onClose: () -> Void
    /// 제목만 남기고 접거나 다시 편다. 창 높이를 바꾸는 일이라 창 주인이 처리한다.
    let onToggleCollapse: () -> Void
    /// 맨 앞 ↔ 맨 뒤. 창 레벨을 바꾸는 일이라 역시 창 주인이 처리한다.
    let onToggleDepth: () -> Void

    @State private var item: ReferenceItem
    @State private var draft: String
    @State private var isHovering = false
    @State private var saveTask: Task<Void, Never>?

    init(
        item: ReferenceItem,
        repository: ReferenceRepository,
        onClose: @escaping () -> Void,
        onToggleCollapse: @escaping () -> Void,
        onToggleDepth: @escaping () -> Void
    ) {
        self.repository = repository
        self.onClose = onClose
        self.onToggleCollapse = onToggleCollapse
        self.onToggleDepth = onToggleDepth
        _item = State(initialValue: item)
        _draft = State(initialValue: item.body)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            StickyNoteShape(color: item.color, cornerSize: 18)
            VStack(alignment: .leading, spacing: 5) {
                header
                // 접었을 때는 본문을 아예 만들지 않는다. 감추기만 하면 접힌 창 안에서
                // 편집기가 계속 살아 키 입력을 가져간다.
                if !item.isWidgetCollapsed {
                    TextEditor(text: $draft)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(item.color.ink)
                        .scrollContentBackground(.hidden)
                        .onChange(of: draft) { _, _ in scheduleSave() }
                }
            }
            .padding(item.isWidgetCollapsed ? 8 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { isHovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: ReferenceChangeBroadcast.name)) { notification in
            guard ReferenceChangeBroadcast.id(from: notification) == item.id else { return }
            reloadFromStore()
        }
        .onDisappear { flush() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            // 손잡이 표시. 창 전체가 드래그 가능하지만 «잡아도 된다» 를 눈으로 알려 준다.
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().frame(width: 11, height: 1.5)
                }
            }
            .foregroundStyle(item.color.ink.opacity(0.42))

            Text(item.displayTitle)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(item.color.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            // 평소에는 숨겨 종이처럼 보이게 두고, 마우스를 올리면 나타난다.
            //
            // **자리는 늘 잡아 두고 투명도만 바꾼다.** 호버할 때마다 버튼을 끼워 넣으면
            // 그만큼 제목이 밀려 글자가 움찔거린다.
            HStack(spacing: 1) {
                // 맨 앞이면 «뒤로 보내기», 맨 뒤면 «앞으로 가져오기».
                iconButton(
                    item.isWidgetBehind ? "arrow.up.square" : "arrow.down.square",
                    help: item.isWidgetBehind ? "맨 앞으로 (모든 창 위)" : "맨 뒤로 (바탕화면 쪽)",
                    action: onToggleDepth
                )
                // 펼쳐져 있으면 «위로 접기», 접혀 있으면 «아래로 펴기». 일기 화면의
                // 접이식 줄이 쓰는 것과 같은 표시라 뜻을 다시 배울 필요가 없다.
                iconButton(
                    item.isWidgetCollapsed ? "chevron.down" : "chevron.up",
                    help: item.isWidgetCollapsed ? "펴기" : "접기",
                    action: {
                        flush()
                        onToggleCollapse()
                    }
                )
                iconButton("xmark", help: "위젯 닫기", action: {
                    flush()
                    onClose()
                })
            }
            .opacity(isHovering ? 1 : 0)
            // 안 보이는 버튼이 클릭을 가로채지 않게 한다.
            .allowsHitTesting(isHovering)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(item.color.ink.opacity(0.7))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - 저장

    /// 타건마다 저장하지 않는다. 본 창과 같은 400ms 규칙을 쓴다.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        persist()
    }

    private func persist() {
        guard draft != item.body else { return }
        guard let updated = try? repository.update(id: item.id, ReferenceChange(body: draft)) else { return }
        item = updated
        ReferenceChangeBroadcast.post(id: item.id)
    }

    private func reloadFromStore() {
        guard let fresh = try? repository.reference(id: item.id) else { return }
        item = fresh
        // 내가 지금 치고 있는 중이면 남의 값으로 덮지 않는다.
        if saveTask == nil { draft = fresh.body }
    }
}
