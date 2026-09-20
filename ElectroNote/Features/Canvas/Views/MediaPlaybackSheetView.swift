import SwiftUI
import AVKit
import AVFoundation
import WebKit

// MARK: - MediaPlaybackSheetView

struct MediaPlaybackSheetView: View {
    let item: MediaPlaybackItem
    let noteURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var playMode: PlaybackMode = .focus
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0.0
    @State private var detectedTitle: String? = nil
    @State private var errorMessage: String? = nil
    @State private var reloadTrigger: Int = 0

    enum PlaybackMode: String, CaseIterable {
        case focus = "Player"
        case web = "YouTube Webseite"
    }

    var cleanVideoID: String {
        extractYouTubeID(from: item.mediaURLString) ?? item.mediaURLString
    }

    var watchURL: URL {
        if let id = extractYouTubeID(from: item.mediaURLString) {
            var urlStr = "https://www.youtube.com/watch?v=\(id)"
            if let t = extractYouTubeTimestamp(from: item.mediaURLString) {
                urlStr += "&t=\(t)"
            }
            urlStr += "&autoplay=1"
            if let url = URL(string: urlStr) {
                return url
            }
        }
        if let url = URL(string: item.mediaURLString), url.scheme != nil {
            return url
        }
        return URL(string: "https://www.youtube.com/watch?v=\(cleanVideoID)&autoplay=1") ?? URL(string: "https://www.youtube.com")!
    }

    private var navigationTitleText: String {
        if let title = item.title, !title.isEmpty, title != "YouTube Video" {
            return title
        }
        if let dt = detectedTitle, !dt.isEmpty {
            return dt
        }
        return item.mediaType == "youtube" ? "YouTube Video" : "Video"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if item.mediaType == "youtube" {
                    YouTubePlayerWebView(
                        url: watchURL,
                        isFocusMode: playMode == .focus,
                        isLoading: $isLoading,
                        progress: $progress,
                        detectedTitle: $detectedTitle,
                        errorMessage: $errorMessage,
                        reloadTrigger: reloadTrigger
                    )
                    .ignoresSafeArea(edges: .bottom)

                    if isLoading && progress < 1.0 {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.red)
                            .padding(.top, 0)
                    }

                    if let err = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.yellow)
                            Text("Video konnte nicht geladen werden")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            HStack(spacing: 16) {
                                Button("Erneut versuchen") {
                                    errorMessage = nil
                                    reloadTrigger += 1
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)

                                Button("In YouTube öffnen") {
                                    UIApplication.shared.open(watchURL)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }
                            .padding(.top, 8)
                        }
                        .padding(28)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.16)))
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    LocalVideoPlayer(filename: item.mediaURLString, noteURL: noteURL)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                if item.mediaType == "youtube" {
                    ToolbarItem(placement: .principal) {
                        Picker("Modus", selection: $playMode) {
                            ForEach(PlaybackMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            reloadTrigger += 1
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white)
                        }
                        .help("Neu laden")

                        Button {
                            UIApplication.shared.open(watchURL)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.white)
                        }
                        .help("In YouTube-App oder Safari öffnen")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }
}

// MARK: - Timestamp Helper

private func extractYouTubeTimestamp(from urlString: String) -> String? {
    if let match = urlString.range(of: "[?&]t=([0-9a-zA-Z]+)", options: .regularExpression) {
        let matched = String(urlString[match])
        if let eqIndex = matched.firstIndex(of: "=") {
            return String(matched[matched.index(after: eqIndex)...])
        }
    }
    return nil
}

// MARK: - YouTube Player WebView (Direct Web Navigation - No Error 150 / 152-4)

private struct YouTubePlayerWebView: UIViewRepresentable {
    let url: URL
    let isFocusMode: Bool
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var detectedTitle: String?
    @Binding var errorMessage: String?
    let reloadTrigger: Int

    private static let focusCSS = """
    ytd-masthead, #masthead-container, #masthead,
    ytm-mobile-topbar-renderer, ytm-pivot-bar-renderer,
    #secondary, ytd-watch-next-secondary-results-renderer,
    #comments, ytd-comments, #below,
    ytm-item-section-renderer, ytm-comments-entry-point-header-renderer,
    ytm-single-column-watch-next-results-renderer,
    yt-mealbar-promo-renderer, ytm-upsell-dialog-renderer,
    #ticker, ytd-banner-promo-renderer, ytd-statement-banner-renderer,
    ytd-popup-container {
        display: none !important;
    }
    html, body {
        background-color: #000000 !important;
        overflow-x: hidden !important;
    }
    #page-manager {
        margin-top: 0 !important;
        padding-top: 0 !important;
    }
    ytd-app {
        --ytd-masthead-height: 0px !important;
    }
    #player-container-outer, #player-container, #movie_player, .player-container {
        margin: 0 auto !important;
    }
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Inject initial script helper for toggling focus CSS
        let escapedCSS = Self.focusCSS.replacingOccurrences(of: "\n", with: " ")
        let initJS = """
        window.__electronoteFocusCSS = "\(escapedCSS)";
        window.__electronoteSetFocusMode = function(enabled) {
            var el = document.getElementById('electronote-focus-css');
            if (enabled) {
                if (!el) {
                    el = document.createElement('style');
                    el.id = 'electronote-focus-css';
                    el.textContent = window.__electronoteFocusCSS;
                    (document.head || document.documentElement).appendChild(el);
                }
            } else {
                if (el) {
                    el.remove();
                }
            }
        };
        """
        let userScript = WKUserScript(source: initJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.setupObservers(for: webView)
        context.coordinator.lastFocusMode = isFocusMode
        context.coordinator.lastReloadTrigger = reloadTrigger

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastFocusMode != isFocusMode {
            context.coordinator.lastFocusMode = isFocusMode
            let js = "if (window.__electronoteSetFocusMode) { window.__electronoteSetFocusMode(\(isFocusMode ? "true" : "false")); }"
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }

        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger
            uiView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: YouTubePlayerWebView
        var lastFocusMode: Bool = true
        var lastReloadTrigger: Int = 0

        private var progressObs: NSKeyValueObservation?
        private var titleObs: NSKeyValueObservation?
        private var loadingObs: NSKeyValueObservation?

        init(_ parent: YouTubePlayerWebView) {
            self.parent = parent
        }

        func setupObservers(for webView: WKWebView) {
            progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = wv.estimatedProgress
                }
            }
            titleObs = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    if let rawTitle = wv.title, !rawTitle.isEmpty {
                        let cleaned = rawTitle.replacingOccurrences(of: " - YouTube", with: "")
                        if !cleaned.trimmingCharacters(in: .whitespaces).isEmpty {
                            self?.parent.detectedTitle = cleaned
                        }
                    }
                }
            }
            loadingObs = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.isLoading = wv.isLoading
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }

            // Apply focus mode styling and start playback if video element is ready
            let js = """
            if (window.__electronoteSetFocusMode) {
                window.__electronoteSetFocusMode(\(lastFocusMode ? "true" : "false"));
            }
            (function() {
                var v = document.querySelector('video');
                if (v && v.paused) {
                    v.play().catch(function(){});
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }

        private func handleError(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Local Video Player

private struct LocalVideoPlayer: View {
    let filename: String
    let noteURL: URL
    @State private var player: AVPlayer? = nil
    @State private var loadError: String? = nil

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.yellow)
                    Text(err)
                        .foregroundColor(.white)
                        .font(.headline)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            setupPlayer()
        }
    }

    private func setupPlayer() {
        let videoURL = noteURL.appendingPathComponent("videos").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: videoURL.path) {
            self.player = AVPlayer(url: videoURL)
        } else {
            let fallbackURL = noteURL.appendingPathComponent("images").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                self.player = AVPlayer(url: fallbackURL)
            } else {
                self.loadError = "Videodatei '\(filename)' konnte nicht gefunden werden."
            }
        }
    }
}
