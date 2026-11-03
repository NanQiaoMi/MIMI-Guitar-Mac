import AppKit
import Foundation
import SwiftUI
import WebKit

struct NativeStudioWebView: NSViewRepresentable {
    @ObservedObject var model: NativeStudioModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        guard let studioRoot = StudioBundleAssets.studioRootURL(),
              let playerRoot = StudioBundleAssets.playerRootURL() else {
            model.engineError = "工坊渲染资源尚未打包。请重新构建应用。"
            return WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        }
        let scheme = StudioResourceSchemeHandler(studioRoot: studioRoot, playerRoot: playerRoot, contentRoot: model.contentRoot)
        context.coordinator.schemeHandler = scheme
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
        configuration.setURLSchemeHandler(scheme, forURLScheme: "mimistudio")
        configuration.userContentController.add(context.coordinator, name: "studio")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = NSColor(calibratedRed: 0.965, green: 0.948, blue: 0.903, alpha: 1)
        context.coordinator.webView = webView
        model.connect(webView)
        guard let url = URL(string: "mimistudio://app/index.html") else { return webView }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle(webView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        @MainActor var model: NativeStudioModel?
        @MainActor weak var webView: WKWebView?
        @MainActor var schemeHandler: StudioResourceSchemeHandler?
        @MainActor private var pendingTeardownWebViews: [ObjectIdentifier: WKWebView] = [:]
        @MainActor private var tearingDownWebViewIDs = Set<ObjectIdentifier>()

        @MainActor init(model: NativeStudioModel) { self.model = model }

        @MainActor func dismantle(_ webView: WKWebView) {
            let webViewID = ObjectIdentifier(webView)
            guard tearingDownWebViewIDs.insert(webViewID).inserted else { return }
            if self.webView === webView {
                self.webView = nil
            }
            pendingTeardownWebViews[webViewID] = webView
            let model = self.model
            Task { @MainActor [self, model, webView] in
                if let model {
                    let prepared = await model.prepareForWebViewTeardown(webView)
                    await disposeAndCleanUp(webView)
                    if !model.disconnect(webView, forceDiscardPending: !prepared) {
                        _ = model.disconnect(webView, forceDiscardPending: true)
                    }
                } else {
                    await disposeAndCleanUp(webView)
                }
                pendingTeardownWebViews.removeValue(forKey: webViewID)
                tearingDownWebViewIDs.remove(webViewID)
                if self.webView == nil {
                    schemeHandler = nil
                    self.model = nil
                }
            }
        }

        @MainActor private func disposeAndCleanUp(_ webView: WKWebView) async {
            await withCheckedContinuation { continuation in
                let gate = NativeStudioAsyncGate<Void>(continuation)
                gate.timeoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    gate.resume(returning: ())
                }
                webView.callAsyncJavaScript("window.NativeStudio && window.NativeStudio.dispose()", arguments: [:], in: nil, in: .page) { _ in
                    Task { @MainActor in
                        gate.resume(returning: ())
                    }
                }
            }
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "studio")
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "studio", message.frameInfo.isMainFrame,
                  let url = message.frameInfo.request.url, url.scheme == "mimistudio", url.host == "app",
                  let payload = message.body as? [String: Any],
                  let sourceWebView = message.webView else { return }
            DispatchQueue.main.async { [weak self, sourceWebView] in
                guard let self, self.webView === sourceWebView else { return }
                self.model?.receive(payload, from: sourceWebView)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url, url.scheme == "mimistudio", url.host == "app",
                  url.path == "/index.html", url.query == nil, url.fragment == nil else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, self.webView === webView, self.model?.webView === webView else { return }
                self.model?.engineError = "工坊页面加载失败：\(message)"
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, self.webView === webView, self.model?.webView === webView else { return }
                self.model?.engineError = "工坊页面加载失败：\(message)"
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
