import SwiftUI
import WebKit

// MARK: - ElektroSimWebSheetView

struct ElektroSimWebSheetView: View {
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var loadProgress: Double = 0.0
    @State private var reloadTrigger = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ElektroSimWebViewRepresentable(
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    loadProgress: $loadProgress,
                    reloadTrigger: $reloadTrigger,
                    onInsert: { image in
                        onInsert(image)
                        dismiss()
                    },
                    onClose: {
                        dismiss()
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView(value: loadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .frame(height: 3)
                        .zIndex(10)
                }
            }
            .navigationTitle("Elektro-Planer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        reloadTrigger.toggle()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Website neu laden")
                }
            }
        }
    }
}

// MARK: - WKWebView Representable

private struct ElektroSimWebViewRepresentable: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var loadProgress: Double
    @Binding var reloadTrigger: Bool

    let onInsert: (UIImage) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "electroNote")

        // User script: ensure window.webkit.messageHandlers.electroNote detection flag is active
        let bridgeInitScript = WKUserScript(
            source: "window.__IS_ELECTRONOTE_NATIVE__ = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeInitScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false

        // Observe loading progress
        context.coordinator.progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { wv, _ in
            DispatchQueue.main.async {
                self.loadProgress = wv.estimatedProgress
                self.canGoBack = wv.canGoBack
                self.canGoForward = wv.canGoForward
            }
        }

        // Load elektrosimulator.de with electronote app parameter
        let urlString = "https://elektrosimulator.de/?app=electronote"
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            webView.load(request)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger
            uiView.reload()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: ElektroSimWebViewRepresentable
        weak var webView: WKWebView?
        var progressObservation: NSKeyValueObservation?
        var lastReloadTrigger: Bool = false

        init(_ parent: ElektroSimWebViewRepresentable) {
            self.parent = parent
            self.lastReloadTrigger = parent.reloadTrigger
        }

        deinit {
            progressObservation?.invalidate()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "electroNote")
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "electroNote",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else {
                return
            }

            if action == "insertCircuit" {
                guard let imageStr = body["imageData"] as? String else { return }
                if let image = decodeBase64Image(imageStr) {
                    DispatchQueue.main.async {
                        self.parent.onInsert(image)
                    }
                }
            } else if action == "close" {
                DispatchQueue.main.async {
                    self.parent.onClose()
                }
            }
        }

        private func decodeBase64Image(_ dataString: String) -> UIImage? {
            var raw = dataString
            if let commaIndex = raw.firstIndex(of: ",") {
                raw = String(raw[raw.index(after: commaIndex)...])
            }
            guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else {
                return nil
            }
            return UIImage(data: data)
        }

        // MARK: - Navigation Delegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}
