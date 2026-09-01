import SwiftUI
import Foundation
import Combine

@MainActor
final class SyncViewModel: ObservableObject {

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sync state

    enum SyncState: Equatable {
        case idle, syncing, done(String), failed(String)
        var isActive: Bool { if case .syncing = self { return true }; return false }
    }

    @Published var credentials: NextcloudCredentials?
    @Published var syncState: SyncState  = .idle
    @Published var lastSynced: Date?
    @Published var progressMessage: String?

    // MARK: - Login flow

    @Published var loginFlow = NextcloudLoginFlow()

    // MARK: - Nextcloud file browser

    @Published var isBrowsing    = false
    @Published var browserItems: [DAVFile] = []
    @Published var browserPath:  [DAVFile] = []
    @Published var browserLoading = false
    @Published var browserError: String?

    var currentBrowsePath: String { browserPath.last?.davPath ?? "" }

    // MARK: - Init

    let localRoot: URL

    init(localRoot: URL = FileService.defaultRootURL) {
        self.localRoot = localRoot
        credentials = NextcloudCredentials.load()
        lastSynced  = UserDefaults.standard.object(forKey: "nc_last_synced") as? Date

        loginFlow.onSuccess = { [weak self] creds in
            self?.credentials = creds
        }

        // Forward loginFlow changes so SyncSettingsView re-renders when
        // loginFlow.loginURL / isLoading / errorMessage change.
        loginFlow.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Login / Logout

    func connect(serverURL: String) { loginFlow.start(serverURL: serverURL) }

    func logout() {
        NextcloudCredentials.logout()
        credentials      = nil
        syncState        = .idle
        lastSynced       = nil
        progressMessage  = nil
        browserPath      = []
        browserItems     = []
    }

    // MARK: - Sync

    func sync() {
        guard let creds = credentials else { return }
        syncState       = .syncing
        progressMessage = "Vorbereitung…"

        Task {
            let client = WebDAVClient(credentials: creds)
            let engine = SyncEngine(client: client, localRoot: localRoot)
            let result = await engine.sync { [weak self] msg in
                Task { @MainActor in self?.progressMessage = msg }
            }

            lastSynced = Date()
            UserDefaults.standard.set(lastSynced, forKey: "nc_last_synced")
            progressMessage = nil

            syncState = result.errors.isEmpty
                ? .done(result.summary)
                : .failed(result.errors.first ?? "Unbekannter Fehler")
        }
    }

    // MARK: - File browser

    func openBrowser() {
        guard credentials != nil else { return }
        browserPath  = []
        browserError = nil
        isBrowsing   = true
        Task { await loadItems(path: "") }
    }

    func navigateInto(_ folder: DAVFile) {
        browserPath.append(folder)
        Task { await loadItems(path: folder.davPath) }
    }

    func navigateUp() {
        _ = browserPath.popLast()
        Task { await loadItems(path: currentBrowsePath) }
    }

    func navigateTo(index: Int) {
        guard index >= 0 && index < browserPath.count else {
            browserPath = []
            Task { await loadItems(path: "") }
            return
        }
        browserPath = Array(browserPath.prefix(index + 1))
        Task { await loadItems(path: currentBrowsePath) }
    }

    func refresh() async {
        await loadItems(path: currentBrowsePath)
    }

    private func loadItems(path: String) async {
        guard let creds = credentials else { return }
        browserLoading = true
        browserError   = nil
        do {
            let items = try await WebDAVClient(credentials: creds).propfind(path: path, depth: "1")
            browserItems = items
                .filter { $0.davPath != path }
                .sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) <
                          ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
        } catch {
            browserError = error.localizedDescription
        }
        browserLoading = false
    }

    // MARK: - PDF import from Nextcloud

    func downloadToTemp(file: DAVFile) async -> URL? {
        guard let creds = credentials else { return nil }
        do {
            let data    = try await WebDAVClient(credentials: creds).get(path: file.davPath)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            browserError = "Download fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }
}
