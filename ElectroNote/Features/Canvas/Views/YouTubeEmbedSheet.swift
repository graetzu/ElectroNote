import SwiftUI
import WebKit

// MARK: - YouTube Video ID Extractor

func extractYouTubeID(from urlString: String) -> String? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    // 1. Check youtu.be/<id>
    if let match = trimmed.range(of: "(?<=youtu.be/)[a-zA-Z0-9_-]{11}", options: .regularExpression) {
        return String(trimmed[match])
    }
    // 2. Check /watch?v=<id>
    if let match = trimmed.range(of: "(?<=v=)[a-zA-Z0-9_-]{11}", options: .regularExpression) {
        return String(trimmed[match])
    }
    // 3. Check /embed/<id>
    if let match = trimmed.range(of: "(?<=embed/)[a-zA-Z0-9_-]{11}", options: .regularExpression) {
        return String(trimmed[match])
    }
    // 4. Check /shorts/<id>
    if let match = trimmed.range(of: "(?<=shorts/)[a-zA-Z0-9_-]{11}", options: .regularExpression) {
        return String(trimmed[match])
    }
    // 5. Bare 11-char ID
    if trimmed.count == 11, trimmed.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil {
        return trimmed
    }
    return nil
}

// MARK: - Interactive YouTube WebView Representable

struct YouTubeLiveWebView: UIViewRepresentable {
    @Binding var currentURL: URL?
    @Binding var pageTitle: String
    @Binding var detectedVideoID: String?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var progress: Double

    var requestedAction: YouTubeNavigationAction?
    let onActionHandled: () -> Void
    let onWebViewCreated: (WKWebView) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.setupObservers(for: webView)
        onWebViewCreated(webView)

        let initial = currentURL ?? URL(string: "https://www.youtube.com")!
        webView.load(URLRequest(url: initial))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let action = requestedAction {
            DispatchQueue.main.async {
                switch action {
                case .goBack:
                    if uiView.canGoBack { uiView.goBack() }
                case .goForward:
                    if uiView.canGoForward { uiView.goForward() }
                case .reload:
                    uiView.reload()
                case .load(let url):
                    uiView.load(URLRequest(url: url))
                }
                onActionHandled()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    enum YouTubeNavigationAction: Equatable {
        case goBack
        case goForward
        case reload
        case load(URL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: YouTubeLiveWebView
        private var urlObs: NSKeyValueObservation?
        private var titleObs: NSKeyValueObservation?
        private var progressObs: NSKeyValueObservation?
        private var backObs: NSKeyValueObservation?
        private var forwardObs: NSKeyValueObservation?

        init(_ parent: YouTubeLiveWebView) {
            self.parent = parent
        }

        func setupObservers(for webView: WKWebView) {
            urlObs = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.updateState(wv) }
            }
            titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.updateState(wv) }
            }
            progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = wv.estimatedProgress
                }
            }
            backObs = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.canGoBack = wv.canGoBack
                }
            }
            forwardObs = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.canGoForward = wv.canGoForward
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            updateState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            updateState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        private func updateState(_ webView: WKWebView) {
            parent.currentURL = webView.url
            if let urlStr = webView.url?.absoluteString {
                parent.detectedVideoID = extractYouTubeID(from: urlStr)
            } else {
                parent.detectedVideoID = nil
            }

            if var title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                if title.hasSuffix(" - YouTube") {
                    title = String(title.dropLast(10))
                }
                if title != "YouTube" && !title.isEmpty {
                    parent.pageTitle = title
                }
            }
        }
    }
}

// MARK: - YouTubeEmbedSheet (Direct Interactive Browser)

struct YouTubeEmbedSheet: View {
    let onEmbed: (MediaInsertion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchOrURLText: String = ""
    @State private var currentURL: URL? = URL(string: "https://www.youtube.com")
    @State private var pageTitle: String = ""
    @State private var detectedVideoID: String? = nil
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0.0

    @State private var pendingAction: YouTubeLiveWebView.YouTubeNavigationAction? = nil
    @State private var webViewInstance: WKWebView? = nil

    @State private var isEmbedding: Bool = false
    @State private var customTitle: String = ""
    @State private var previewThumbnail: UIImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Navigation & Search Bar
                HStack(spacing: 8) {
                    Button {
                        pendingAction = .goBack
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(canGoBack ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                            .clipShape(Circle())
                    }
                    .disabled(!canGoBack)

                    Button {
                        pendingAction = .goForward
                    } label: {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(canGoForward ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                            .clipShape(Circle())
                    }
                    .disabled(!canGoForward)

                    Button {
                        pendingAction = .reload
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(Circle())
                    }

                    // Search / Address bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))

                        TextField("YouTube suchen oder Link einfügen…", text: $searchOrURLText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .keyboardType(.webSearch)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                performSearchOrNavigation()
                            }

                        if !searchOrURLText.isEmpty {
                            Button {
                                searchOrURLText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    Button {
                        performSearchOrNavigation()
                    } label: {
                        Text("Los")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemGroupedBackground))

                // Progress Bar
                if isLoading && progress < 1.0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .frame(height: 2)
                } else {
                    Divider()
                }

                // Center: Real YouTube Web View
                ZStack {
                    YouTubeLiveWebView(
                        currentURL: $currentURL,
                        pageTitle: $pageTitle,
                        detectedVideoID: $detectedVideoID,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        isLoading: $isLoading,
                        progress: $progress,
                        requestedAction: pendingAction,
                        onActionHandled: { pendingAction = nil },
                        onWebViewCreated: { wv in webViewInstance = wv }
                    )
                    .ignoresSafeArea(edges: .bottom)

                    // Bottom Insertion Floating Card
                    VStack {
                        Spacer()
                        bottomActionCard
                    }
                }
            }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                checkClipboardOrInitialURL()
            }
            .onChange(of: detectedVideoID) { _, newID in
                if let id = newID {
                    customTitle = pageTitle
                    loadThumbnailPreview(for: id)
                } else {
                    previewThumbnail = nil
                }
            }
            .onChange(of: pageTitle) { _, newTitle in
                if customTitle.isEmpty || customTitle == "YouTube" {
                    customTitle = newTitle
                }
            }
        }
    }

    // MARK: - Bottom Action Card

    @ViewBuilder
    private var bottomActionCard: some View {
        if let videoID = detectedVideoID {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Thumbnail
                    if let thumb = previewThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                                    .shadow(radius: 2)
                            )
                    } else {
                        ZStack {
                            Color.red.opacity(0.15)
                            Image(systemName: "play.rectangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 24))
                        }
                        .frame(width: 80, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Title & ID
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customTitle.isEmpty ? (pageTitle.isEmpty ? "YouTube Video" : pageTitle) : customTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundColor(.primary)

                        Text("ID: \(videoID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Confirm Embed Button
                Button {
                    embedCurrentVideo(videoID: videoID)
                } label: {
                    HStack(spacing: 6) {
                        if isEmbedding {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Video in Notizbuch einfügen")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.red.opacity(0.3), radius: 6, y: 3)
                }
                .disabled(isEmbedding)
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            // Hint pill when user is browsing
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.red)
                Text("Tippe auf ein beliebiges Video, um es einzufügen")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.1), radius: 6, y: 2)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Actions

    private func checkClipboardOrInitialURL() {
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty,
           let clipID = extractYouTubeID(from: clip) {
            let target = "https://www.youtube.com/watch?v=\(clipID)"
            searchOrURLText = target
            if let url = URL(string: target) {
                currentURL = url
                pendingAction = .load(url)
            }
        }
    }

    private func performSearchOrNavigation() {
        let text = searchOrURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if text.hasPrefix("http://") || text.hasPrefix("https://"), let url = URL(string: text) {
            pendingAction = .load(url)
        } else if let id = extractYouTubeID(from: text), let url = URL(string: "https://www.youtube.com/watch?v=\(id)") {
            pendingAction = .load(url)
        } else if let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") {
            pendingAction = .load(searchURL)
        }
    }

    private func loadThumbnailPreview(for videoID: String) {
        Task {
            let thumb = await downloadAndComposeThumbnail(videoID: videoID)
            await MainActor.run {
                self.previewThumbnail = thumb
            }
        }
    }

    private func embedCurrentVideo(videoID: String) {
        isEmbedding = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            var thumb = previewThumbnail
            if thumb == nil {
                thumb = await downloadAndComposeThumbnail(videoID: videoID)
            }
            if thumb == nil {
                thumb = await captureWebViewSnapshot()
            }
            let finalThumb = thumb ?? placeholderThumbnail()

            let finalTitle = customTitle.isEmpty ? (pageTitle.isEmpty ? "YouTube Video" : pageTitle) : customTitle
            let item = MediaInsertion(
                thumbnail: finalThumb,
                mediaType: "youtube",
                mediaURLString: videoID,
                title: finalTitle
            )

            await MainActor.run {
                onEmbed(item)
                dismiss()
            }
        }
    }

    private func captureWebViewSnapshot() async -> UIImage? {
        guard let wv = webViewInstance else { return nil }
        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: wv.bounds.width, height: min(wv.bounds.height, 400))
            wv.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func placeholderThumbnail() -> UIImage {
        let size = CGSize(width: 480, height: 270)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 54, weight: .bold)
            if let icon = UIImage(systemName: "play.rectangle.fill", withConfiguration: config) {
                icon.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(at: CGPoint(x: (size.width - icon.size.width) / 2, y: (size.height - icon.size.height) / 2))
            }
        }
    }

    private func downloadAndComposeThumbnail(videoID: String) async -> UIImage? {
        let urls = [
            "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg",
            "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg",
            "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
        ]

        var baseImage: UIImage? = nil
        for u in urls {
            if let url = URL(string: u),
               let (data, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let img = UIImage(data: data), img.size.width > 120 {
                baseImage = img
                break
            }
        }

        guard let raw = baseImage else { return nil }

        // Render card with YouTube badge
        let renderer = UIGraphicsImageRenderer(size: raw.size)
        return renderer.image { ctx in
            raw.draw(in: CGRect(origin: .zero, size: raw.size))

            // Centered YouTube play button
            let playW: CGFloat = min(raw.size.width * 0.26, 90)
            let playH: CGFloat = playW * 0.7
            let playRect = CGRect(
                x: (raw.size.width - playW) / 2,
                y: (raw.size.height - playH) / 2,
                width: playW,
                height: playH
            )

            // Red rounded rect with shadow
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            let path = UIBezierPath(roundedRect: playRect, cornerRadius: playH * 0.28)
            UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.95).setFill()
            path.fill()

            // Reset shadow
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            // White triangle
            let triPath = UIBezierPath()
            let triW = playW * 0.32
            let triH = playH * 0.42
            let triX = playRect.midX - triW * 0.38
            let triY = playRect.midY

            triPath.move(to: CGPoint(x: triX, y: triY - triH / 2))
            triPath.addLine(to: CGPoint(x: triX + triW, y: triY))
            triPath.addLine(to: CGPoint(x: triX, y: triY + triH / 2))
            triPath.close()

            UIColor.white.setFill()
            triPath.fill()
        }
    }
}
