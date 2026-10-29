import AppKit
import Foundation
import SwiftUI
import WebKit

struct NativePlayerWebView: NSViewRepresentable {
    let model: NativePlayerModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        guard let playerRoot = PlayerBundleAssets.rootURL(), let source = model.source else {
            model.playerRootError = "播放器资源或谱面来源不存在。请重建应用资源包。"
            return FocusedPlayerWebView(frame: .zero, configuration: WKWebViewConfiguration())
        }

        do {
            let schemeHandler = try PlayerResourceSchemeHandler(
                playerRoot: playerRoot,
                contentRoot: model.contentRoot,
                source: source
            )
            context.coordinator.schemeHandler = schemeHandler
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = []
#if MIMI_RUNTIME_DIAGNOSTICS
            if let diagnosticScript = ProcessInfo.processInfo.environment["MIMI_RUNTIME_AUDIO_SCRIPT"], !diagnosticScript.isEmpty {
                configuration.userContentController.addUserScript(WKUserScript(
                    source: diagnosticScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            }
#endif
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "mimiplayer")
            configuration.userContentController.add(context.coordinator, name: "mimi")

            let webView = FocusedPlayerWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            webView.allowsBackForwardNavigationGestures = false
            webView.onScoreSpace = { [weak model] in model?.togglePlayback() }
            webView.onViewportLayout = { [weak model, weak webView] in
                guard let model, let webView, let contentView = webView.window?.contentView else { return }
                model.setPageViewportWidth(Double(contentView.bounds.width))
            }
            webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
            context.coordinator.webView = webView
            model.connect(webView)

            guard let entryURL = URL(string: "mimiplayer://app/index.html") else {
                model.playerRootError = "无法建立本地谱面页面地址。"
                return webView
            }
            model.pageLoadStarted()
            webView.load(URLRequest(url: entryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            return webView
        } catch {
            model.playerRootError = error.localizedDescription
            return FocusedPlayerWebView(frame: .zero, configuration: WKWebViewConfiguration())
        }
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle(webView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        @MainActor weak var model: NativePlayerModel?
        @MainActor weak var webView: WKWebView?
        @MainActor var schemeHandler: PlayerResourceSchemeHandler?

        @MainActor
        init(model: NativePlayerModel) {
            self.model = model
        }

        @MainActor
        func dismantle(_ webView: WKWebView) {
            webView.stopLoading()
            webView.callAsyncJavaScript(
                "window.NativePlayer && window.NativePlayer.dispose()",
                arguments: [:],
                in: nil,
                in: .page,
                completionHandler: { [self, weak webView] _ in
                    guard let webView else { return }
                    webView.stopLoading()
                    webView.configuration.userContentController.removeScriptMessageHandler(forName: "mimi")
                    webView.navigationDelegate = nil
                    webView.uiDelegate = nil
                    if model?.webView === webView { model?.webView = nil }
                    self.webView = nil
                    self.schemeHandler = nil
                }
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mimi",
                  message.frameInfo.isMainFrame,
                  let url = message.frameInfo.request.url,
                  url.scheme == "mimiplayer",
                  url.host == "app" else { return }
            let body = message.body
            DispatchQueue.main.async { [weak self] in
                guard let model = self?.model else { return }
                model.receive(body)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url,
                  url.scheme == "mimiplayer",
                  url.host == "app",
                  url.path == "/index.html",
                  url.query == nil,
                  url.fragment == nil else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self] in
                self?.model?.pageNavigationFailed(message)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self] in
                self?.model?.pageNavigationFailed(message)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}

private final class FocusedPlayerWebView: WKWebView {
    var onScoreSpace: (() -> Void)?
    var onViewportLayout: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        onViewportLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onViewportLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if event.keyCode == 49 && event.modifierFlags.intersection(disallowedModifiers).isEmpty {
            onScoreSpace?()
            return
        }
        super.keyDown(with: event)
    }
}
