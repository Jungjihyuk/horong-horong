import SwiftUI
import AppKit

struct VaultBrowserView: View {
    @State private var viewModel: VaultViewModel
    @AppStorage private var storedPath: String
    @State private var creation: Creation?
    @State private var deletingNode: VaultNode?
    @State private var newName = ""
    private struct Creation: Identifiable {
        let id = UUID()
        let directory: Bool
        let parent: URL?
    }
    init(kind: VaultKind, repository: VaultRepository, locations: VaultLocationGateway) {
        _viewModel = State(initialValue: VaultViewModel(kind: kind, repository: repository, locations: locations))
        _storedPath = AppStorage(wrappedValue: "", "mind.\(kind.title.lowercased()).root")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            treePane.frame(width: viewModel.isTreeVisible ? 280 : 0).frame(maxHeight: .infinity).clipped()
                .disabled(!viewModel.isTreeVisible).accessibilityHidden(!viewModel.isTreeVisible)
            if viewModel.isTreeVisible { Divider() }
            VStack(spacing: 0) {
                documentToolbar
                Divider()
                if let error = viewModel.actionError {
                    HStack {
                        Text(error).font(.caption).textSelection(.enabled)
                        Spacer()
                        if viewModel.hasConflict {
                            Button("디스크 버전 열기") { Task { await viewModel.discardDraft() } }
                            Button("내 변경 사본 저장") { Task { await viewModel.saveConflictCopy() } }
                        } else { Button("닫기") { viewModel.actionError = nil } }
                    }.padding(10).background(PopoverChrome.accentSoft)
                }
                if let url = viewModel.selectedURL, url.pathExtension.lowercased() == "md", viewModel.snapshot != nil {
                    MarkdownDocumentView(viewModel: viewModel, reading: viewModel.isReadingMode)
                } else {
                    ContentUnavailableView {
                        Label(viewModel.loadError == nil ? "문서를 선택하세요" : "문서를 읽을 수 없습니다", systemImage: "doc.text")
                    } description: {
                        Text(viewModel.loadError ?? "새 노트를 만들거나 왼쪽 폴더에서 문서를 선택하세요.")
                    } actions: {
                        if viewModel.location == nil { Button("루트 폴더 선택") { Task { await viewModel.chooseRoot() } } }
                        if let url = viewModel.selectedURL { Button("Finder에서 열기") { NSWorkspace.shared.open(url) } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverChrome.surface)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTreeVisible)
        .task { await viewModel.initialize(); await viewModel.observe() }
        .onChange(of: storedPath) { _, _ in Task { await viewModel.initialize() } }
        .sheet(item: $creation) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(item.directory ? "새 폴더" : "새 노트").font(.headline)
                TextField("이름", text: $newName).textFieldStyle(.roundedBorder).onSubmit { create(item) }
                let parentFolder = item.parent ?? viewModel.location?.root
                let rootPath = viewModel.location?.root.path ?? ""
                let folderName = parentFolder.map { folder in
                    folder.path == rootPath ? "루트 (최상위)" : folder.path.replacingOccurrences(of: rootPath + "/", with: "")
                } ?? "루트"
                HStack(spacing: 6) {
                    Text("생성 위치:").font(.caption).foregroundStyle(.secondary)
                    Text(folderName).font(.caption.monospaced()).foregroundStyle(.primary)
                    Spacer()
                    if let root = viewModel.location?.root, item.parent?.path != root.path {
                        Button("루트에 생성") {
                            creation = Creation(directory: item.directory, parent: root)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                HStack {
                    Spacer()
                    Button("취소") { creation = nil }.keyboardShortcut(.cancelAction)
                    Button("생성") { create(item) }.keyboardShortcut(.defaultAction).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 400)
        }
        .confirmationDialog(
            "\(deletingNode?.name ?? "항목")을(를) 삭제하시겠습니까?",
            isPresented: Binding(get: { deletingNode != nil }, set: { if !$0 { deletingNode = nil } }),
            titleVisibility: .visible
        ) {
            Button("휴지통으로 이동", role: .destructive) {
                if let node = deletingNode {
                    deletingNode = nil
                    Task { await viewModel.delete(at: node.url) }
                }
            }
            Button("취소", role: .cancel) {
                deletingNode = nil
            }
        } message: {
            Text("삭제된 항목은 macOS 휴지통으로 이동합니다.")
        }
    }
    private var treePane: some View {
        VStack(spacing: 10) {
            HStack {
                Text(viewModel.kind.title).font(.headline)
                Spacer()
                Button { startCreation(directory: false) } label: { Image(systemName: "square.and.pencil") }.help("새 노트 생성")
                Button { startCreation(directory: true) } label: { Image(systemName: "folder.badge.plus") }.help("새 폴더 생성")
                Button { Task { await viewModel.reload() } } label: { Image(systemName: "arrow.clockwise") }.help("다시 읽기")
            }.buttonStyle(.plain).disabled(viewModel.location == nil).padding(.horizontal, 14).padding(.top, 16)
            TextField("파일명 검색", text: $viewModel.searchText).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
            if viewModel.isScanning && viewModel.roots.isEmpty { ProgressView().padding() }
            List {
                ForEach(viewModel.visibleRows) { row in
                    VaultFileRow(node: row.node, depth: row.depth, expanded: viewModel.expandedFolders.contains(row.node.url), selected: viewModel.selectedURL == row.node.url) {
                        if row.node.isDirectory {
                            if !viewModel.expandedFolders.insert(row.node.url).inserted { viewModel.expandedFolders.remove(row.node.url) }
                        } else { Task { await viewModel.open(row.node.url) } }
                    }.equatable().contextMenu {
                        let targetFolder = row.node.isDirectory ? row.node.url : row.node.url.deletingLastPathComponent()
                        Button {
                            startCreation(directory: false, parent: targetFolder)
                        } label: {
                            Label("이 폴더에 새 노트", systemImage: "square.and.pencil")
                        }
                        Button {
                            startCreation(directory: true, parent: targetFolder)
                        } label: {
                            Label("이 폴더에 새 폴더", systemImage: "folder.badge.plus")
                        }
                        Divider()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([row.node.url])
                        } label: {
                            Label("Finder에서 보기", systemImage: "macwindow")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deletingNode = row.node
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            if let error = viewModel.loadError { Text(error).font(.caption).padding(.horizontal) }
            Button { Task { await viewModel.chooseRoot() } } label: {
                HStack {
                    Image(systemName: "folder")
                    Text(viewModel.location?.root.lastPathComponent ?? "루트 폴더 선택").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
            }.buttonStyle(.plain).help(viewModel.location?.root.path ?? "로컬 폴더 선택").padding(14)
        }.frame(width: 280).frame(maxHeight: .infinity).background(PopoverChrome.surfaceAlt)
    }
    private var documentToolbar: some View {
        HStack(spacing: 12) {
            Button { viewModel.isTreeVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                .help(viewModel.isTreeVisible ? "폴더 트리 접기" : "폴더 트리 펼치기").accessibilityLabel("폴더 트리 표시 전환")
            if viewModel.openTabs.isEmpty {
                Text(viewModel.kind.title).font(.headline).lineLimit(1)
                Spacer()
            } else {
                tabStrip
            }
            if viewModel.snapshot != nil {
                Text(viewModel.isSaving ? "저장 중…" : viewModel.hasConflict ? "충돌 · 초안 보관" : viewModel.isDirty ? "저장 대기" : viewModel.canEdit ? "저장됨" : "참조 문서").font(.caption).foregroundStyle(.secondary)
                // 토글 버튼은 라벨이 «다음 동작»이라 지금 어느 모드인지 읽히지 않았다.
                Picker("보기 모드", selection: $viewModel.isReadingMode) {
                    Text("읽기").tag(true)
                    Text("편집").tag(false)
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(!viewModel.canEdit)
                Button("저장") { Task { await viewModel.save() } }.disabled(!viewModel.isDirty || viewModel.hasConflict)
            }
            if let url = viewModel.selectedURL { Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
        }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 12)
    }
    /// 열어 둔 문서를 브라우저 탭처럼 늘어놓는다. 트리에서 새 문서를 고르면 오른쪽에 붙는다.
    private var tabStrip: some View {
        let rootPath = (viewModel.location?.reference.path ?? "") + "/"
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.openTabs, id: \.self) { url in
                        VaultTabChip(
                            title: url.deletingPathExtension().lastPathComponent,
                            path: url.path.replacingOccurrences(of: rootPath, with: ""),
                            active: viewModel.selectedURL == url,
                            dirty: viewModel.selectedURL == url && viewModel.isDirty,
                            select: { Task { await viewModel.select(url) } },
                            close: { Task { await viewModel.close(url) } }
                        ).equatable().id(url)
                    }
                }.padding(.vertical, 1)
            }
            // 트리에서 연 문서의 탭이 화면 밖에 생기면 고른 줄 모른다.
            .onChange(of: viewModel.selectedURL) { _, url in
                guard let url else { return }
                proxy.scrollAfterLayout(to: url, animation: .easeOut(duration: 0.15))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func startCreation(directory: Bool, parent: URL? = nil) {
        newName = ""
        let targetParent: URL?
        if let parent {
            targetParent = parent
        } else if let selected = viewModel.selectedURL {
            targetParent = selected.deletingLastPathComponent()
        } else {
            targetParent = viewModel.location?.root
        }
        creation = Creation(directory: directory, parent: targetParent)
    }
    private func create(_ item: Creation) { let name = newName; creation = nil; Task { await viewModel.create(name: name, directory: item.directory, parent: item.parent) } }
}

/// 탭 하나. 값만 받아 `Equatable` 이므로 다른 탭이 바뀌어도 다시 그리지 않는다.
private struct VaultTabChip: View, Equatable {
    let title: String
    let path: String
    let active: Bool
    let dirty: Bool
    let select: () -> Void
    let close: () -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.path == rhs.path && lhs.active == rhs.active && lhs.dirty == rhs.dirty
    }
    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text").font(.system(size: 10))
                    Text(title).font(.callout.weight(active ? .semibold : .regular)).lineLimit(1)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: close) {
                Image(systemName: dirty ? "circle.fill" : "xmark")
                    .font(.system(size: dirty ? 6 : 8, weight: .bold))
                    .frame(width: 12, height: 12).contentShape(Rectangle())
            }.buttonStyle(.plain).help(dirty ? "저장 대기 · 닫기" : "탭 닫기").accessibilityLabel("\(title) 탭 닫기")
        }
        .foregroundStyle(active ? PopoverChrome.ink : PopoverChrome.inkSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: 190)
        .background(active ? PopoverChrome.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
        .help(path)
    }
}

private struct VaultFileRow: View, Equatable {
    let node: VaultNode
    let depth: Int
    let expanded: Bool
    let selected: Bool
    let action: () -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.node == rhs.node && lhs.depth == rhs.depth && lhs.expanded == rhs.expanded && lhs.selected == rhs.selected }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? (expanded ? "chevron.down" : "chevron.right") : "circle.fill")
                    .font(.system(size: node.isDirectory ? 9 : 3)).frame(width: 12).opacity(node.isDirectory ? 1 : 0)
                Image(systemName: node.isDirectory ? "folder" : "doc.text")
                Text(node.name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12).padding(.vertical, 5).padding(.horizontal, 5)
            .background(selected ? PopoverChrome.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
