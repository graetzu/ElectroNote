import SwiftUI

// MARK: - YouTubeEmbedSheet

struct YouTubeEmbedSheet: View {
    let onEmbed: (MediaInsertion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var titleText: String = ""
    @State private var detectedVideoID: String? = nil
    @State private var previewImage: UIImage? = nil
    @State private var isLoadingPreview = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("YouTube Link") {
                    HStack {
                        TextField("https://youtu.be/... oder youtube.com/...", text: $urlText)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: urlText) { _, newURL in
                                parseAndLoadPreview(newURL)
                            }

                        if !urlText.isEmpty {
                            Button {
                                urlText = ""
                                detectedVideoID = nil
                                previewImage = nil
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            parseAndLoadPreview(urlText)
                        }
                    } label: {
                        Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                            .font(.footnote)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                if let videoID = detectedVideoID {
                    Section("Vorschau") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.red)
                                Text("Video-ID: \(videoID)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            if isLoadingPreview {
                                HStack {
                                    Spacer()
                                    ProgressView("Lade Vorschaubild…")
                                    Spacer()
                                }
                                .frame(height: 180)
                            } else if let img = previewImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            TextField("Titel / Notiz (optional)", text: $titleText)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button {
                            confirmEmbed()
                        } label: {
                            HStack {
                                Spacer()
                                Label("In Notiz einbetten", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("YouTube einbetten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear {
                checkClipboardForYouTubeLink()
            }
        }
    }

    private func checkClipboardForYouTubeLink() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else { return }
        if extractYouTubeID(from: clip) != nil {
            urlText = clip
            parseAndLoadPreview(clip)
        }
    }

    private func parseAndLoadPreview(_ text: String) {
        guard let videoID = extractYouTubeID(from: text) else {
            detectedVideoID = nil
            previewImage = nil
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Ungültiger YouTube-Link. Bitte einen Link wie https://youtu.be/... oder youtube.com/watch?v=... eingeben."
            } else {
                errorMessage = nil
            }
            return
        }

        errorMessage = nil
        detectedVideoID = videoID
        isLoadingPreview = true

        Task {
            let thumb = await downloadAndComposeThumbnail(videoID: videoID)
            await MainActor.run {
                self.previewImage = thumb
                self.isLoadingPreview = false
            }
        }
    }

    private func extractYouTubeID(from urlString: String) -> String? {
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

    private func downloadAndComposeThumbnail(videoID: String) async -> UIImage? {
        let urls = [
            "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg",
            "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
        ]

        var baseImage: UIImage? = nil
        for u in urls {
            if let url = URL(string: u),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                baseImage = img
                break
            }
        }

        guard let raw = baseImage else { return nil }

        // Render card with YouTube badge
        let renderer = UIGraphicsImageRenderer(size: raw.size)
        return renderer.image { ctx in
            raw.draw(in: CGRect(origin: .zero, size: raw.size))

            // Draw centered YouTube play button
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

    private func confirmEmbed() {
        guard let videoID = detectedVideoID, let img = previewImage else { return }
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = MediaInsertion(
            thumbnail: img,
            mediaType: "youtube",
            mediaURLString: videoID,
            title: title.isEmpty ? nil : title
        )
        onEmbed(item)
        dismiss()
    }
}
