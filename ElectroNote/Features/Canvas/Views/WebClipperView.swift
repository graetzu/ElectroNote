import SwiftUI
import WebKit

// MARK: - Result Action

enum ClipperAction {
    case insertImage(UIImage, extractedText: String)
    case insertImageAndStickyNote(UIImage, extractedText: String)
    case insertTextOnly(String)
}

// MARK: - WebClipperView

struct WebClipperView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (ClipperAction) -> Void

    @State private var urlString = "https://www.google.com"
    @State private var activeURL: URL? = URL(string: "https://www.google.com")
    @State private var urlInput = "https://www.google.com"
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webViewCoordinator: WebClipperCoordinator? = nil

    // Snipping tool state
    @State private var isSnippingMode = false
    @State private var snippingRect: CGRect = .zero
    @State private var isDraggingSnipping = false

    // Result & OCR Preview state
    @State private var capturedImage: UIImage? = nil
    @State private var recognizedText: String = ""
    @State private var isRunningOCR = false
    @State private var showResultSheet = false

    private let quickBookmarks: [(name: String, icon: String, url: String)] = [
        ("Google", "magnifyingglass", "https://www.google.com"),
        ("Wikipedia", "book.fill", "https://de.wikipedia.org"),
        ("Elektronik-Kompendium", "bolt.fill", "https://www.elektronik-kompendium.de"),
        ("VDE Normen Info", "shield.fill", "https://www.vde-verlag.de")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Address & Navigation Bar
                navigationHeader

                // Quick Bookmarks Bar
                bookmarksBar

                Divider()

                // Web Content with Snipping Overlay
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        WebClipperRepresentable(
                            activeURL: $activeURL,
                            isLoading: $isLoading,
                            canGoBack: $canGoBack,
                            canGoForward: $canGoForward,
                            onCoordinatorReady: { coord in
                                self.webViewCoordinator = coord
                            }
                        )

                        if isLoading {
                            ProgressView()
                                .scaleEffect(1.2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.08))
                        }

                        // Interactive Snipping Tool Overlay
                        if isSnippingMode {
                            SnippingOverlayView(
                                bounds: geo.size,
                                selectionRect: $snippingRect,
                                isDragging: $isDraggingSnipping,
                                onConfirm: {
                                    captureCroppedArea()
                                },
                                onCancel: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isSnippingMode = false
                                        snippingRect = .zero
                                    }
                                }
                            )
                        }
                    }
                }

                Divider()

                // Bottom Action Bar
                bottomActionBar
            }
            .navigationTitle("Web-Recherche & Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .sheet(isPresented: $showResultSheet) {
                if let image = capturedImage {
                    ClipperResultSheet(
                        image: image,
                        recognizedText: recognizedText,
                        isRunningOCR: isRunningOCR,
                        onAction: { action in
                            showResultSheet = false
                            onCapture(action)
                            dismiss()
                        },
                        onRetake: {
                            showResultSheet = false
                            capturedImage = nil
                            recognizedText = ""
                        }
                    )
                }
            }
        }
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        HStack(spacing: 8) {
            Button {
                webViewCoordinator?.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!canGoBack)

            Button {
                webViewCoordinator?.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!canGoForward)

            Button {
                webViewCoordinator?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            // URL input field
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                TextField("Adresse eingeben oder suchen…", text: $urlInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        submitURL()
                    }

                if !urlInput.isEmpty {
                    Button {
                        urlInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)

            Button("Öffnen") {
                submitURL()
            }
            .buttonStyle(.bordered)
            .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Bookmarks Bar

    private var bookmarksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickBookmarks, id: \.url) { bm in
                    Button {
                        loadURL(bm.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: bm.icon)
                                .font(.caption2)
                            Text(bm.name)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            Button {
                captureFullView()
            } label: {
                Label("Ganze Ansicht aufnehmen", systemImage: "viewfinder")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSnippingMode.toggle()
                    if isSnippingMode {
                        snippingRect = .zero
                    }
                }
            } label: {
                Label(isSnippingMode ? "Zuschneiden aktiv" : "Bereich ausschneiden…", systemImage: "crop")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSnippingMode ? .orange : .blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Actions & Capturing

    private func submitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            loadURL(trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            loadURL("https://\(trimmed)")
        } else {
            // Google Search query
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            loadURL("https://www.google.com/search?q=\(query)")
        }
    }

    private func loadURL(_ string: String) {
        urlInput = string
        if let url = URL(string: string) {
            activeURL = url
        }
    }

    private func captureFullView() {
        guard let coordinator = webViewCoordinator else { return }
        Task { @MainActor in
            if let image = await coordinator.takeSnapshot(cropRect: nil) {
                processCapturedImage(image)
            }
        }
    }

    private func captureCroppedArea() {
        guard let coordinator = webViewCoordinator else { return }
        let rect = snippingRect
        isSnippingMode = false
        snippingRect = .zero

        Task { @MainActor in
            if let image = await coordinator.takeSnapshot(cropRect: rect.width > 20 && rect.height > 20 ? rect : nil) {
                processCapturedImage(image)
            }
        }
    }

    private func processCapturedImage(_ image: UIImage) {
        capturedImage = image
        showResultSheet = true
        isRunningOCR = true
        recognizedText = ""

        Task {
            let text = await OCRService.shared.extractText(from: image)
            await MainActor.run {
                self.recognizedText = text
                self.isRunningOCR = false
            }
        }
    }
}

// MARK: - Snipping Overlay View

struct SnippingOverlayView: View {
    let bounds: CGSize
    @Binding var selectionRect: CGRect
    @Binding var isDragging: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint = .zero

    var body: some View {
        ZStack {
            // Darkened background with cut-out hole
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .reverseMask {
                    if selectionRect.width > 0 && selectionRect.height > 0 {
                        Rectangle()
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            isDragging = true
                            if startPoint == .zero {
                                startPoint = value.startLocation
                            }
                            let originX = min(startPoint.x, value.location.x)
                            let originY = min(startPoint.y, value.location.y)
                            let width = abs(value.location.x - startPoint.x)
                            let height = abs(value.location.y - startPoint.y)
                            selectionRect = CGRect(x: originX, y: originY, width: width, height: height)
                        }
                        .onEnded { _ in
                            isDragging = false
                            startPoint = .zero
                        }
                )

            // Selection Rectangle Outline
            if selectionRect.width > 0 && selectionRect.height > 0 {
                Rectangle()
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .background(Rectangle().fill(Color.blue.opacity(0.08)))
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)

                // Dimension Tag
                Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height)) pt")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .cornerRadius(4)
                    .position(x: selectionRect.midX, y: max(20, selectionRect.minY - 14))
            }

            // Instructions & Confirmation Controls
            VStack {
                HStack {
                    Text("Ziehe mit Stift oder Finger einen Ausschnitt auf")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                    Spacer()
                    Button("Abbrechen") {
                        onCancel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                }
                .padding()

                Spacer()

                if selectionRect.width > 30 && selectionRect.height > 30 && !isDragging {
                    Button {
                        onConfirm()
                    } label: {
                        Label("Diesen Ausschnitt einfügen", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .shadow(radius: 8)
                    .padding(.bottom, 24)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Clipper Result & OCR Sheet

struct ClipperResultSheet: View {
    let image: UIImage
    let recognizedText: String
    let isRunningOCR: Bool
    let onAction: (ClipperAction) -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String = ""
    @State private var copiedToast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Preview
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .padding(.top, 12)

                    // OCR Recognized Text Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Erkannter Text (Apple Vision OCR)", systemImage: "text.viewfinder")
                                .font(.headline)

                            Spacer()

                            if isRunningOCR {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Erkenne Text…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if !isRunningOCR && recognizedText.isEmpty {
                            Text("Kein gedruckter Text im Bild gefunden.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            TextEditor(text: $editedText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120, maxHeight: 180)
                                .padding(8)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)

                    Divider()

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            onAction(.insertImage(image, extractedText: editedText))
                        } label: {
                            Label("Als Grafik auf Seite einfügen", systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        if !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                onAction(.insertImageAndStickyNote(image, extractedText: editedText))
                            } label: {
                                Label("Bild + Text als Notizzettel einfügen", systemImage: "note.text.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                onAction(.insertTextOnly(editedText))
                            } label: {
                                Label("Nur erkannten Text in Notiz einfügen", systemImage: "text.quote")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                UIPasteboard.general.string = editedText
                                copiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedToast = false
                                }
                            } label: {
                                Label(copiedToast ? "In Zwischenablage kopiert!" : "Text in Zwischenablage kopieren",
                                      systemImage: copiedToast ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Screenshot Vorschau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen") {
                        onRetake()
                    }
                }
            }
            .onAppear {
                editedText = recognizedText
            }
            .onChange(of: recognizedText) { _, newText in
                editedText = newText
            }
        }
    }
}

// MARK: - WebKit Representable & Coordinator

struct WebClipperRepresentable: UIViewRepresentable {
    @Binding var activeURL: URL?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    let onCoordinatorReady: (WebClipperCoordinator) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView
        onCoordinatorReady(context.coordinator)

        if let url = activeURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = activeURL, uiView.url != url && !uiView.isLoading {
            uiView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> WebClipperCoordinator {
        WebClipperCoordinator(self)
    }
}

final class WebClipperCoordinator: NSObject, WKNavigationDelegate {
    var parent: WebClipperRepresentable
    weak var webView: WKWebView?

    init(_ parent: WebClipperRepresentable) {
        self.parent = parent
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func takeSnapshot(cropRect: CGRect?) async -> UIImage? {
        guard let wv = webView else { return nil }

        let config = WKSnapshotConfiguration()
        if let rect = cropRect, rect.width > 10 && rect.height > 10 {
            config.rect = rect
        }

        return try? await wv.takeSnapshot(configuration: config)
    }

    // WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        parent.isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        parent.isLoading = false
        parent.canGoBack = webView.canGoBack
        parent.canGoForward = webView.canGoForward
        if let currentURL = webView.url {
            parent.activeURL = currentURL
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        parent.isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        parent.isLoading = false
    }
}

// MARK: - Reverse Mask Helper

private extension View {
    @ViewBuilder
    func reverseMask<Mask: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> Mask
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}
