import SwiftUI
import AVKit
import WebKit

// MARK: - MediaPlaybackSheetView

struct MediaPlaybackSheetView: View {
    let item: MediaPlaybackItem
    let noteURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if item.mediaType == "youtube" {
                    YouTubeWebView(videoID: item.mediaURLString)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    LocalVideoPlayer(filename: item.mediaURLString, noteURL: noteURL)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(item.title ?? (item.mediaType == "youtube" ? "YouTube Video" : "Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            // Check in images folder or direct path
            let fallbackURL = noteURL.appendingPathComponent("images").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                self.player = AVPlayer(url: fallbackURL)
            } else {
                self.loadError = "Videodatei '\(filename)' konnte nicht gefunden werden."
            }
        }
    }
}

// MARK: - YouTube Web View

private struct YouTubeWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.bounces = false

        // Load YouTube embed with privacy mode (youtube-nocookie.com)
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { margin:0; padding:0; box-sizing:border-box; background:#000; }
          html, body { width:100%; height:100%; overflow:hidden; display:flex; align-items:center; justify-content:center; }
          iframe { width:100vw; height:56.25vw; max-height:100vh; max-width:177.78vh; border:none; }
        </style>
        </head>
        <body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=1&playsinline=1&modestbranding=1&rel=0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen>
        </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
