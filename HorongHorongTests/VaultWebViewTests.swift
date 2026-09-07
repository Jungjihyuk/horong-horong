import XCTest
import WebKit
@testable import 호롱호롱

@MainActor
final class VaultWebViewTests: XCTestCase {
    private func wait(_ web: WKWebView, for expression: String, timeout: TimeInterval = 20) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        let body = (try? await web.evaluateJavaScript("document.body.innerText")) as? String ?? ""
        XCTFail("WebKit 대기 시간 초과: \(expression)\n\(body.prefix(1500))")
    }

    private func host(source: String, reading: Bool) async throws -> (VaultViewModel, MarkdownDocumentView.Coordinator, WKWebView, NSWindow, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Note.md")
        try source.write(to: url, atomically: true, encoding: .utf8)
        let vm = VaultViewModel(kind: .knowledge, repository: FileSystemVaultRepository())
        await vm.load(vault: root)
        await vm.open(url)
        vm.isReadingMode = reading
        let coordinator = MarkdownDocumentView.Coordinator(viewModel: vm, reading: vm.isReadingMode)
        let web = MarkdownDocumentView.makeWebView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        return (vm, coordinator, web, window, root, url)
    }

    /// CodeMirror 는 기본 테마를 `.<생성클래스> .cm-content` 로 주입해 특이도가 우리 CSS 보다 높다.
    /// 그래서 여백 «값»만 고치면 조용히 무시된다. 눈으로 판정하지 않도록 계산된 스타일로 못 박는다.
    func testGuttersAndPropertyEditorSurviveCodeMirrorBaseTheme() async throws {
        let source = """
        ---
        started: 2026-09-07
        tags:
          - Study
          - Concept
        ---
        # 제목

        - [!] 중요한 일
        """
        let (vm, coordinator, web, window, root, url) = try await host(source: source, reading: true)
        defer {
            coordinator.watchdog?.cancel()
            web.configuration.userContentController.removeScriptMessageHandler(forName: "vault")
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: root)
        }

        try await wait(web, for: "document.querySelector('#reading .prop-row') !== null")
        let editorHidden = try await web.evaluateJavaScript("document.querySelector('#editor').hidden") as? Bool
        XCTAssertEqual(editorHidden, true, "읽기 모드에서는 편집기가 숨는다")
        let readingGutter = try await web.evaluateJavaScript("(() => { const el = document.querySelector('#reading'); return parseFloat(getComputedStyle(el).paddingLeft) / el.getBoundingClientRect().width * 100 })()") as? Double
        XCTAssertEqual(readingGutter ?? 0, 20, accuracy: 1, "본문 좌우 여백은 vault 의 file-width.css 와 같은 20% 다")
        let rowCount = try await web.evaluateJavaScript("document.querySelectorAll('#reading .prop-row').length") as? Int
        XCTAssertEqual(rowCount, 2)
        let chipCount = try await web.evaluateJavaScript("document.querySelectorAll('#reading [data-key=\"tags\"] .prop-chip').length") as? Int
        XCTAssertEqual(chipCount, 2)
        let leaked = try await web.evaluateJavaScript("document.querySelector('#reading').innerText.includes('---')") as? Bool
        XCTAssertEqual(leaked, false, "원문 YAML 구분선이 드러나면 안 된다")

        // vault 의 checkboxes 스니펫이 실제로 붙었는지. `[!]` 표식이 노랑을 받으면
        // data-task 생성 → sanitizer 통과 → 스니펫 로드 → 규칙 적용이 전부 성립한 것이다.
        // (file:// 스타일시트는 cssRules 접근이 교차 출처로 막혀 계산된 값으로 본다.)
        let taskColor = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('#reading input[data-task=\"!\"]')).backgroundColor") as? String
        XCTAssertEqual(taskColor, "rgb(224, 172, 0)", "checkboxes 스니펫의 --color-yellow 가 적용되지 않았다")

        vm.isReadingMode = false
        coordinator.reading = false
        coordinator.update()
        try await wait(web, for: "!document.querySelector('#editor').hidden && document.querySelector('.cm-content') !== null")
        let editorGutter = try await web.evaluateJavaScript("(() => { const el = document.querySelector('.cm-content'); return parseFloat(getComputedStyle(el).paddingLeft) / el.getBoundingClientRect().width * 100 })()") as? Double
        XCTAssertEqual(editorGutter ?? 0, 20, accuracy: 1)
        let font = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.cm-scroller')).fontFamily") as? String
        XCTAssertFalse(font?.contains("monospace") ?? true, "본문 글꼴이 monospace 로 되돌아갔다: \(font ?? "없음")")
        // 편집 모드에서도 속성은 위젯으로 남아야 한다 — 원문 YAML 을 알아야 고치는 상태가 문제였다.
        try await wait(web, for: "document.querySelector('.cm-content .prop-row') !== null")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source, "열람·모드 전환은 원문을 변경하지 않는다")
    }

    func testBundledEditorRendersAndExecutesDataviewInWebKit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        ---
        tags: [Study]
        priority: 2
        ---
        # **문서 호환 검증**

        > [!note] 속성과 서식
        > ==강조==와 **굵게**, [[Other|다른 노트]]

        | 도구 | 설명 |
        | --- | --- |
        | **CodeMirror** | 라이브 편집 |

        ```dataviewjs
        dv.table(["노트", "개수"], [["**전체 문서**", dv.pages().length]]);
        dv.container.createEl("p", {text: "Dataview 실행 완료"});
        ```

        ```mermaid
        graph LR
          A[파일] --> B[문서]
        ```
        """
        let url = root.appendingPathComponent("Note.md")
        try source.write(to: url, atomically: true, encoding: .utf8)
        try "# Other".write(to: root.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)
        let vm = VaultViewModel(kind: .knowledge, repository: FileSystemVaultRepository())
        await vm.load(vault: root)
        await vm.open(url)
        vm.isReadingMode = true
        let coordinator = MarkdownDocumentView.Coordinator(viewModel: vm, reading: vm.isReadingMode)
        let web = MarkdownDocumentView.makeWebView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        defer { coordinator.watchdog?.cancel(); web.configuration.userContentController.removeScriptMessageHandler(forName: "vault"); window.orderOut(nil) }
        try await wait(web, for: "document.querySelector('#reading strong') !== null")
        try await wait(web, for: "document.querySelector('#reading').innerText.includes('Dataview 실행 완료')")
        try await wait(web, for: "document.querySelector('#reading svg') !== null")
        let tableCount = try await web.evaluateJavaScript("document.querySelectorAll('#reading table').length") as? Int
        XCTAssertEqual(tableCount, 2)
        XCTAssertNil(vm.actionError)
        let image = try await web.takeSnapshot(configuration: nil)
        if let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/horong-vault-preview.png"))
        }
        vm.isReadingMode = false
        coordinator.reading = false
        coordinator.update()
        try await wait(web, for: "!document.querySelector('#editor').hidden && document.querySelector('.cm-content') !== null")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source, "열람·모드 전환은 원문을 변경하지 않는다")
    }
}
