import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// 웹 편집기는 변경 의도만 전달하고 파일 접근은 ViewModel 계약을 통한다.
struct MarkdownDocumentView: NSViewRepresentable {
    let viewModel: VaultViewModel
    /// 보기 모드를 **값으로** 받는다. `viewModel.isReadingMode` 를 코디네이터가 직접 읽으면
    /// 부모 body 가 그 프로퍼티를 관찰하지 않아 `updateNSView` 자체가 호출되지 않는다
    /// (툴바의 `$viewModel.isReadingMode` 는 Binding 을 만들 뿐 값을 읽지 않는다).
    /// 그래서 읽기로 바꿔도 웹뷰가 편집기인 채로 남았다.
    let reading: Bool
    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel, reading: reading) }
    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(coordinator: context.coordinator)
    }
    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "vault")
        configuration.setURLSchemeHandler(coordinator, forURLScheme: "vault-resource")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        // 웹 계층 문제를 추측으로 좁히지 않으려면 Safari 웹 인스펙터가 필요하다.
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        coordinator.webView = webView
        coordinator.load()
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.reading = reading
        context.coordinator.update()
    }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.watchdog?.cancel()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "vault")
        nsView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
        let viewModel: VaultViewModel
        /// 부모 View 가 넘겨 준 보기 모드. 갱신 경로를 한 곳으로 모으려고 여기에 보관한다.
        var reading: Bool
        weak var webView: WKWebView?
        var ready = false
        var watchdog: Task<Void, Never>?
        private var disabledBlocks: Set<String> = []
        private var lastState = ""
        private var resourceTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        private var anchor = ""
        init(viewModel: VaultViewModel, reading: Bool) { self.viewModel = viewModel; self.reading = reading }
        func load() {
            ready = false
            lastState = ""
            guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "VaultEditor") else {
                viewModel.actionError = "문서 편집기 리소스를 찾지 못했습니다. 앱을 다시 빌드하세요."
                return
            }
            webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        func update() {
            guard ready, let location = viewModel.location, let url = viewModel.selectedURL else { return }
            let path = String(url.path.dropFirst(location.reference.path.count + 1))
            let theme = ["surface": css(PopoverChrome.surface), "ink": css(PopoverChrome.ink), "accent": css(PopoverChrome.accent), "muted": css(PopoverChrome.inkSecondary), "card": css(PopoverChrome.surfaceAlt), "divider": css(PopoverChrome.divider)]
            // 타이핑마다 다시 초기화하면 IME·커서·undo가 깨지므로 native 교체만 전달한다.
            let stateKey = "\(path)|\(viewModel.documentVersion)|\(viewModel.indexVersion)|\(reading)|\(viewModel.canEdit)|\(theme)|\(anchor)|\(disabledBlocks.sorted())"
            guard stateKey != lastState else { return }
            lastState = stateKey
            guard let documents = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(viewModel.indexedDocuments)) else { return }
            let state: [String: Any] = ["path": path, "source": viewModel.markdown, "version": viewModel.documentVersion, "indexVersion": viewModel.indexVersion, "reading": reading, "readOnly": !viewModel.canEdit, "documents": documents, "theme": theme, "disabledBlocks": Array(disabledBlocks), "anchor": anchor]
            webView?.callAsyncJavaScript("window.setVaultState(state)", arguments: ["state": state], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result { self?.viewModel.actionError = "문서 표시 오류: \(error.localizedDescription)" }
            }
            anchor = ""
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Dataview iframe이 native 저장 메시지를 직접 보내는 것을 거부한다.
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready": ready = true; update()
            case "change":
                guard let text = body["text"] as? String, let path = body["path"] as? String,
                      let reference = viewModel.location?.reference,
                      reference.appendingPathComponent(path).standardizedFileURL == viewModel.selectedURL?.standardizedFileURL else { return }
                viewModel.edit(text)
            case "save": Task { await viewModel.save() }
            case "open":
                guard let path = body["path"] as? String else { return }
                anchor = body["anchor"] as? String ?? ""
                Task { await viewModel.openRelative(path); update() }
            case "link":
                guard let target = body["target"] as? String else { return }
                Task { await viewModel.followWikiLink(target) }
            case "external":
                guard let raw = body["url"] as? String, let url = URL(string: raw), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
                NSWorkspace.shared.open(url)
            case "read":
                guard let id = body["id"] as? Int, let path = body["path"] as? String else { return }
                Task {
                    var response: [String: Any] = ["id": id]
                    do {
                        let data = try await viewModel.resource(path)
                        guard let text = String(data: data, encoding: .utf8) else { throw VaultError.unavailable }
                        response["text"] = text
                    } catch { response["error"] = error.localizedDescription }
                    webView?.callAsyncJavaScript("window.vaultReadResult(response)", arguments: ["response": response], in: nil, in: .page, completionHandler: nil)
                }
            case "started":
                guard let id = body["id"] as? String else { return }
                watchdog?.cancel()
                watchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self else { return }
                    disabledBlocks.insert(id)
                    // WebContent가 멈춰도 원문은 native ViewModel에 남아 있다.
                    load()
                }
            case "finished": watchdog?.cancel()
            default: break
            }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.isFileURL == true || url?.scheme == "vault-resource" || url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            let id = ObjectIdentifier(urlSchemeTask)
            resourceTasks[id] = Task {
                defer { resourceTasks.removeValue(forKey: id) }
                do {
                    guard let url = urlSchemeTask.request.url, let path = String(url.path.dropFirst()).removingPercentEncoding else { throw VaultError.unavailable }
                    let data = try await viewModel.resource(path)
                    guard !Task.isCancelled else { return }
                    let mime = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                } catch { if !Task.isCancelled { urlSchemeTask.didFailWithError(error) } }
            }
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { resourceTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel() }
        private func css(_ color: Color) -> String {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .textColor
            return "rgba(\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255)),\(c.alphaComponent))"
        }
    }
}
