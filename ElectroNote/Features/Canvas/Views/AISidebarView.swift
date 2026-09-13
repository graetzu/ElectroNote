import SwiftUI
import SafariServices

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

// MARK: - AI Bookmark

/// A saved link into one of the AI providers (e.g. a specific ongoing chat/project).
/// SFSafariViewController never reveals which URL is currently displayed, so these can
/// only be added manually (paste a link copied from Safari's own share sheet).
struct AIBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var urlString: String

    var url: URL? { URL(string: urlString) }

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
    }
}

// MARK: - AISidebarView

struct AISidebarView: View {
    @ObservedObject var vm: InfiniteNotebookViewModel
    let onClose: () -> Void

    @AppStorage("electroNote_lastAIProvider") private var selectedProviderRaw: String = AIProvider.chatGPT.rawValue
    @State private var selectedProvider: AIProvider = .chatGPT

    @State private var toastMessage: String? = nil
    @State private var isExtracting = false
    @State private var showCustomQuestionDialog = false
    @State private var customQuestionText = ""

    @State private var bookmarks: [AIBookmark] = []
    @State private var activeBookmarkURL: URL? = nil
    @State private var showBookmarksSheet = false
    @State private var isApplyingBookmark = false
    private static let bookmarksDefaultsKey = "electroNote_aiBookmarks"

    /// The URL actually shown in the browser: a picked bookmark overrides the
    /// selected provider's default start page until a different provider tab is tapped.
    private var currentURL: URL {
        activeBookmarkURL ?? selectedProvider.url
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            quickActionBar

            Divider()

            ZStack(alignment: .top) {
                // Google refuses to complete "Sign in with Google" inside an embedded
                // WKWebView ("This browser or app may not be secure"). SFSafariViewController
                // is a trusted, persistent-cookie browser context Google accepts, so login
                // works normally here — including for accounts that only registered via Google.
                // .id() forces a fresh SFSafariViewController whenever the provider changes,
                // since its URL can't be changed after creation.
                AISafariView(url: currentURL, onDismiss: onClose)
                    .id(currentURL)

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
            loadBookmarks()
        }
        .onChange(of: selectedProvider) { _, newProvider in
            selectedProviderRaw = newProvider.rawValue
            if isApplyingBookmark {
                // This change came from picking a bookmark below, not from tapping a
                // provider tab — don't clear the bookmark URL we just switched to.
                isApplyingBookmark = false
            } else {
                activeBookmarkURL = nil
            }
        }
        .onChange(of: bookmarks) { _, _ in
            saveBookmarks()
        }
        .sheet(isPresented: $showBookmarksSheet) {
            AIBookmarksSheet(bookmarks: $bookmarks) { bookmark in
                guard let url = bookmark.url else { return }
                if let matchingProvider = AIProvider.allCases.first(where: { url.host?.contains($0.url.host ?? "___") == true }),
                   matchingProvider != selectedProvider {
                    isApplyingBookmark = true
                    selectedProviderRaw = matchingProvider.rawValue
                    selectedProvider = matchingProvider
                }
                activeBookmarkURL = url
            }
        }
        .alert("Frage an die KI stellen", isPresented: $showCustomQuestionDialog) {
            TextField("Deine Frage zum Dokument...", text: $customQuestionText)
            Button("Übernehmen") {
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

            // Bookmarks
            Button {
                showBookmarksSheet = true
            } label: {
                Image(systemName: activeBookmarkURL != nil ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel("Lesezeichen")

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
                    Text("Seite kopieren")
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

            // Quick Action: Screenshot of the current page (no OCR/text extraction — lets
            // the AI actually see diagrams/sketches that text extraction alone would miss).
            Button {
                copyScreenshotToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                    Text("Screenshot")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedProvider.brandColor.opacity(0.12))
                .foregroundColor(selectedProvider.brandColor)
                .cornerRadius(8)
            }

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
                    Text("Frage vorbereiten…")
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Context Transfer

    /// SFSafariViewController doesn't expose a way to run JavaScript from outside, so the
    /// prompt can no longer be auto-inserted into the chat's text field like with the old
    /// WKWebView. It's copied to the clipboard instead — the user pastes it with one long-press.
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

            let focusRaw = UserDefaults.standard.string(forKey: "electroNote_aiDomainFocus") ?? AIDomainFocus.electrical.rawValue
            let focus = AIDomainFocus(rawValue: focusRaw) ?? .electrical
            let focusInstruction: String
            if focus == .custom {
                focusInstruction = UserDefaults.standard.string(forKey: "electroNote_aiCustomPrompt") ?? ""
            } else {
                focusInstruction = focus.promptPrefix
            }
            let instructionPrefix = focusInstruction.isEmpty ? "" : "[\(focusInstruction)]\n\n"

            let prompt: String
            if let q = customQuestion, !q.isEmpty {
                prompt = """
                \(instructionPrefix)Hier ist der Inhalt aus meinen Notizen / Dokumentseiten:
                ---
                \(contextText)
                ---

                Aufgabe / Frage:
                \(q)
                """
            } else {
                prompt = """
                \(instructionPrefix)Hier ist der Inhalt aus meinen Notizen / Dokumentseiten:
                ---
                \(contextText)
                ---

                Bitte analysiere den Inhalt und frage mich, was du dazu erklären oder zusammenfassen sollst.
                """
            }

            UIPasteboard.general.string = prompt

            showToast("In Zwischenablage kopiert – im \(selectedProvider.rawValue)-Feld einfügen")
        }
    }

    /// Puts a screenshot of the currently visible notebook page (not the whole screen —
    /// this sidebar is never included, see captureVisiblePageImage) on the clipboard, so
    /// it can be pasted straight into the AI provider's chat as an image attachment.
    private func copyScreenshotToClipboard() {
        guard let image = vm.captureCurrentPageImageForAI() else {
            showToast("Konnte keinen Screenshot erstellen")
            return
        }
        UIPasteboard.general.image = image
        showToast("Screenshot kopiert – im \(selectedProvider.rawValue)-Feld einfügen")
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

    // MARK: - Bookmark Persistence

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarksDefaultsKey),
              let decoded = try? JSONDecoder().decode([AIBookmark].self, from: data) else { return }
        bookmarks = decoded
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarksDefaultsKey)
    }
}

// MARK: - AI Bookmarks Sheet

struct AIBookmarksSheet: View {
    @Binding var bookmarks: [AIBookmark]
    let onSelect: (AIBookmark) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "Keine Lesezeichen",
                        systemImage: "bookmark",
                        description: Text("Speichere häufig genutzte Chats oder Projekte für schnellen Zugriff.")
                    )
                } else {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            onSelect(bookmark)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.name)
                                    .foregroundColor(.primary)
                                Text(bookmark.urlString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        bookmarks.remove(atOffsets: indexSet)
                    }
                }
            }
            .navigationTitle("Lesezeichen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Lesezeichen hinzufügen")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAIBookmarkView { newBookmark in
                    bookmarks.append(newBookmark)
                }
            }
        }
    }
}

// MARK: - Add AI Bookmark

struct AddAIBookmarkView: View {
    let onSave: (AIBookmark) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var urlString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Elektro-Ausbildung Projekt", text: $name)
                }
                Section("Link") {
                    TextField("https://...", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button {
                        if let clip = UIPasteboard.general.string {
                            urlString = clip
                        }
                    } label: {
                        Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                    }
                }
                Section {
                    Text("Tipp: Öffne den gewünschten Chat in der KI-Sidebar, tippe unten in der Safari-Leiste auf Teilen → „Kopieren“, und füge den Link hier ein.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Neues Lesezeichen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard URL(string: trimmedURL) != nil else { return }
                        onSave(AIBookmark(name: trimmedName.isEmpty ? trimmedURL : trimmedName, urlString: trimmedURL))
                        dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Safari-based AI Browser

/// Hosts a provider's chat website in Apple's Safari View Controller instead of a raw
/// WKWebView. Unlike WKWebView, Google fully trusts this context for "Sign in with Google" —
/// there's no separate window/cookie hand-off involved, so accounts that only ever
/// registered via Google work here too. Session cookies persist across app launches
/// the same way they do in Safari itself.
struct AISafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
