import Foundation
import SwiftUI
import Combine

@MainActor
final class UnifiedSyncManager: ObservableObject {
    static let shared = UnifiedSyncManager()

    @Published var activeProvider: SyncProvider {
        didSet {
            UserDefaults.standard.set(activeProvider.rawValue, forKey: "electroNote_activeSyncProvider")
        }
    }

    @Published var autoSyncOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncOnLaunch, forKey: "electroNote_autoSyncOnLaunch")
        }
    }

    @Published var autoSyncOnSave: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncOnSave, forKey: "electroNote_autoSyncOnSave")
        }
    }

    @Published var isSyncing = false
    @Published var progressMessage: String?
    @Published var lastSummary: String?
    @Published var errorMessage: String?

    // Provider Engines
    let nextcloudVM: SyncViewModel
    let icloudEngine: ICloudSyncEngine
    let googleDriveEngine: GoogleDriveSyncEngine

    private var cancellables = Set<AnyCancellable>()

    init(localRoot: URL = FileService.defaultRootURL) {
        let savedProviderRaw = UserDefaults.standard.string(forKey: "electroNote_activeSyncProvider") ?? SyncProvider.none.rawValue
        self.activeProvider = SyncProvider(rawValue: savedProviderRaw) ?? .none

        self.autoSyncOnLaunch = UserDefaults.standard.bool(forKey: "electroNote_autoSyncOnLaunch")
        self.autoSyncOnSave = UserDefaults.standard.bool(forKey: "electroNote_autoSyncOnSave")

        self.nextcloudVM = SyncViewModel(localRoot: localRoot)
        self.icloudEngine = ICloudSyncEngine(localRoot: localRoot)
        self.googleDriveEngine = GoogleDriveSyncEngine(localRoot: localRoot)

        // Forward sub-engine changes
        nextcloudVM.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        icloudEngine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        googleDriveEngine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - Last Synced

    var lastSyncedDate: Date? {
        switch activeProvider {
        case .none: return nil
        case .nextcloud: return nextcloudVM.lastSynced
        case .icloud: return icloudEngine.lastSynced
        case .googleDrive: return googleDriveEngine.lastSynced
        }
    }

    var isConfigured: Bool {
        switch activeProvider {
        case .none: return true
        case .nextcloud: return nextcloudVM.credentials != nil
        case .icloud: return icloudEngine.isICloudAccountActive || icloudEngine.customFolderURL != nil
        case .googleDrive: return googleDriveEngine.isConnected
        }
    }

    // MARK: - Sync Execution

    func syncActiveProvider() {
        guard !isSyncing else { return }

        switch activeProvider {
        case .none:
            return

        case .nextcloud:
            nextcloudVM.sync()

        case .icloud:
            isSyncing = true
            progressMessage = "iCloud wird synchronisiert…"
            Task {
                let res = await icloudEngine.sync { [weak self] msg in
                    Task { @MainActor in self?.progressMessage = msg }
                }
                self.isSyncing = false
                self.progressMessage = nil
                self.lastSummary = res.summary
                if let err = res.errors.first {
                    self.errorMessage = err
                }
            }

        case .googleDrive:
            isSyncing = true
            progressMessage = "Google Drive wird synchronisiert…"
            Task {
                let res = await googleDriveEngine.sync { [weak self] msg in
                    Task { @MainActor in self?.progressMessage = msg }
                }
                self.isSyncing = false
                self.progressMessage = nil
                self.lastSummary = res.summary
                if let err = res.errors.first {
                    self.errorMessage = err
                }
            }
        }
    }
}
