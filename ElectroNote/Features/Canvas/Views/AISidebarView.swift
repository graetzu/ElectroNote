import SwiftUI
import WebKit

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case chatGPT = "ChatGPT"
    case claude  = "Claude"
    case gemini  = "Gemini"

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com")!
        case .claude:  return URL(string: "https://claude.ai/new")!
        case .gemini:  return URL(string: "https://gemini.google.com/app")!
        }
    }

    var icon: String {
        switch self {
        case .chatGPT: return "sparkle"
        case .claude:  return "brain.head.profile"
        case .gemini:  return "stars"
        }
    }

    var brandColor: Color {
        switch self {
        case .chatGPT: return Color(red: 0.06, green: 0.65, blue: 0.53)
        case .claude:  return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .gemini:  return Color(red: 0.25, green: 0.50, blue: 0.95)
        }
    }
}

// MARK: - AISidebarView

struct AISidebarView: View {
    @ObservedObject var vm: InfiniteNotebookViewModel
    let onClose: () -> Void

    @AppStorage("electroNote_lastAIProvider") private var selectedProviderRaw: String = AIProvider.chatGPT.rawValue
    @State private var selectedProvider: AIProvider = .chatGPT

    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var reloadTrigger = false
    @State private var loadProgress: Double = 0.0

    @State private var webViewCoordinator: AIWebViewCoordinator? = nil
    @State private var toastMessage: String? = nil
    @State private var isExtracting = false
    @State private var showCustomQuestionDialog = false
    @State private var customQuestionText = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            quickActionBar

            Divider()

            ZStack(alignment: .top) {
                AIWebViewRepresentable(
                    provider: selectedProvider,
                    isLoading: $isLoading,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    loadProgress: $loadProgress,
                    reloadTrigger: $reloadTrigger,
                    onCoordinatorReady: { coord in
                        self.webViewCoordinator = coord
                    }
                )

                if isLoading {
                    ProgressView(value: loadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: selectedProvider.brandColor))
                        .frame(height: 3)
                        .zIndex(10)
                }

                if let toast = toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
                }
            }
        }
        .frame(width: 440)
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .leading
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: -6, y: 0)
        .onAppear {
            if let saved = AIProvider(rawValue: selectedProviderRaw) {
                selectedProvider = saved
            }
        }
        .onChange(of: selectedProvider) { _, newProvider in
            selectedProviderRaw = newProvider.rawValue
        }
        .alert("Frage an die KI stellen", isPresented: $showCustomQuestionDialog) {
            TextField("Deine Frage zum Dokument...", text: $customQuestionText)
            Button("An \(selectedProvider.rawValue) senden") {
                let q = customQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
                customQuestionText = ""
                if !q.isEmpty {
                    transferContextToAI(customQuestion: q)
                }
            }
            Button("Abbrechen", role: .cancel) {
                customQuestionText = ""
            }
        } message: {
            Text("Der Inhalt der aktuellen Seite wird automatisch als Kontext mitgeschickt.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Provider Tabs
            Picker("KI-Modell", selection: $selectedProvider) {
                ForEach(AIProvider.allCases) { p in
                    Label(p.rawValue, systemImage: p.icon)
                        .tag(p)
                }
            }
            .pickerStyle(.segmented)

            Spacer()

            // Navigation controls
            Button {
                webViewCoordinator?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)

            Button {
                webViewCoordinator?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)

            Button {
                reloadTrigger.toggle()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Quick Action Bar

    private var quickActionBar: some View {
        HStack(spacing: 8) {
            // Quick Action: Current Page
            Button {
                transferContextToAI(customQuestion: nil)
            } label: {
                HStack(spacing: 4) {
                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    Text("Seite übergeben")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedProvider.brandColor.opacity(0.12))
                .foregroundColor(selectedProvider.brandColor)
                .cornerRadius(8)
            }
            .disabled(isExtracting)

            // Preset Questions Menu
            Menu {
                Button {
                    transferContextToAI(customQuestion: "Fasse den Inhalt dieser Seite kurz und übersichtlich in Stichpunkten zusammen.")
                } label: {
                    Label("Seite zusammenfassen", systemImage: "text.badge.checkmark")
                }

                Button {
                    transferContextToAI(customQuestion: "Erkläre die wichtigsten Fachbegriffe, Formeln und Zusammenhänge auf dieser Seite verständlich für Auszubildende.")
                } label: {
                    Label("Fachbegriffe & Formeln erklären", systemImage: "lightbulb")
                }

                Button {
                    transferContextToAI(customQuestion: "Prüfe den Inhalt dieser Seite und die handschriftlichen Notizen auf fachliche Richtigkeit nach DIN VDE.")
                } label: {
                    Label("Auf Richtigkeit prüfen (DIN VDE)", systemImage: "checkmark.shield")
                }

                Button {
                    transferContextToAI(customQuestion: "Erstelle 3 typische Prüfungsfragen inklusive Musterantworten zu diesem Seiteninhalt.")
                } label: {
                    Label("3 Prüfungsfragen erstellen", systemImage: "questionmark.bubble")
                }

                Divider()

                Button {
                    showCustomQuestionDialog = true
                } label: {
                    Label("Eigene Frage mit Notizinhalt...", systemImage: "bubble.left.and.pencil")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.bubble")
                    Text("Frage stellen…")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }

            Spacer()

            // Account status hint
            Text("Abo aktiv")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemFill))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Context Transfer

    private func transferContextToAI(customQuestion: String?) {
        guard !isExtracting else { return }
        isExtracting = true

        Task { @MainActor in
            defer { isExtracting = false }

            let contextText = await vm.collectContextTextForAI()
            guard !contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showToast("Kein Text auf dieser Seite gefunden")
                return
            }

            let prompt: String
            if let q = customQuestion, !q.isEmpty {
                prompt = """
                Hier ist der Inhalt aus meinen Notizen / Dokumentseiten:
                ---
                \(contextText)
                ---

                Aufgabe / Frage:
                \(q)
                """
            } else {
                prompt = """
                Hier ist der Inhalt aus meinen Notizen / Dokumentseiten:
                ---
                \(contextText)
                ---

                Bitte analysiere den Inhalt und frage mich, was du dazu erklären oder zusammenfassen sollst.
                """
            }

            // 1. Copy to system pasteboard for universal 1-tap paste
            UIPasteboard.general.string = prompt

            // 2. Inject directly into the active Web Chat input field
            webViewCoordinator?.injectPrompt(prompt)

            showToast("Notizinhalt an \(selectedProvider.rawValue) übergeben!")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if toastMessage == text {
                    toastMessage = nil
                }
            }
        }
    }
}

// MARK: - WKWebView Representable

struct AIWebViewRepresentable: UIViewRepresentable {
    let provider: AIProvider
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var loadProgress: Double
    @Binding var reloadTrigger: Bool
    let onCoordinatorReady: (AIWebViewCoordinator) -> Void

    func makeCoordinator() -> AIWebViewCoordinator {
        let coord = AIWebViewCoordinator(self)
        onCoordinatorReady(coord)
        return coord
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Persistent data store so user stays logged in across app launches
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Custom modern iPad Safari User-Agent to ensure full desktop/tablet web UI
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

        context.coordinator.webView = webView
        context.coordinator.setupObservations(webView: webView)

        let request = URLRequest(url: provider.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        webView.load(request)
        context.coordinator.currentProvider = provider

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.currentProvider != provider {
            context.coordinator.currentProvider = provider
            let request = URLRequest(url: provider.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            uiView.load(request)
        }

        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger
            uiView.reload()
        }
    }
}

// MARK: - Coordinator & Injection

final class AIWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let parent: AIWebViewRepresentable
    weak var webView: WKWebView?
    var currentProvider: AIProvider?
    var lastReloadTrigger = false
    private var progressObs: NSKeyValueObservation?
    private var canGoBackObs: NSKeyValueObservation?
    private var canGoForwardObs: NSKeyValueObservation?

    init(_ parent: AIWebViewRepresentable) {
        self.parent = parent
        self.lastReloadTrigger = parent.reloadTrigger
    }

    func setupObservations(webView: WKWebView) {
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.parent.loadProgress = wv.estimatedProgress
                self?.parent.isLoading = wv.isLoading
            }
        }
        canGoBackObs = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.parent.canGoBack = wv.canGoBack
            }
        }
        canGoForwardObs = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.parent.canGoForward = wv.canGoForward
            }
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func injectPrompt(_ prompt: String) {
        guard let webView = webView else { return }

        // Sanitize string for JS injection
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [prompt], options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let js = """
        (function() {
            const promptText = \(jsonString)[0];

            // 1. ChatGPT
            let el = document.querySelector('#prompt-textarea') ||
                     document.querySelector('div#prompt-textarea') ||
                     document.querySelector('textarea[data-id="root"]') ||
                     document.querySelector('textarea');

            // 2. Claude (contenteditable paragraph)
            if (!el) {
                el = document.querySelector('div[contenteditable="true"] p') ||
                     document.querySelector('div[contenteditable="true"]') ||
                     document.querySelector('fieldset div[contenteditable]');
            }

            // 3. Gemini (rich-textarea or contenteditable)
            if (!el) {
                el = document.querySelector('rich-textarea div[contenteditable="true"]') ||
                     document.querySelector('textarea.textarea');
            }

            if (el) {
                el.focus();
                if (el.tagName && el.tagName.toLowerCase() === 'textarea') {
                    el.value = promptText;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                } else if (el.isContentEditable) {
                    el.innerText = promptText;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }
                return true;
            }
            return false;
        })();
        """

        webView.evaluateJavaScript(js) { _, _ in }
    }

    // Allow popup windows (for OAuth / Google Sign-In) to load in the same webview
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
