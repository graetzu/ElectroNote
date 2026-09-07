import Foundation
import SwiftUI

@MainActor
final class ICloudSyncEngine: ObservableObject {

    @Published var isSyncing = false
    @Published var lastSynced: Date?
    @Published var lastSummary: String?
    @Published var errorMessage: String?
    @Published var customFolderName: String?

    let localRoot: URL

    private let bookmarkKey = "icloud_custom_folder_bookmark"
    private let lastSyncedKey = "icloud_last_synced"

    init(localRoot: URL = FileService.defaultRootURL) {
        self.localRoot = localRoot
        self.lastSynced = UserDefaults.standard.object(forKey: lastSyncedKey) as? Date
        updateCustomFolderName()
    }

    // MARK: - iCloud Status

    var isICloudAccountActive: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var ubiquityContainerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("ElectroNote", isDirectory: true)
    }

    var customFolderURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                if let newData = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(newData, forKey: bookmarkKey)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    var resolvedSyncURL: URL? {
        if let custom = customFolderURL {
            return custom
        }
        return ubiquityContainerURL
    }

    var statusDescription: String {
        if let customName = customFolderName {
            return "Benutzerdefinierter Ordner: \(customName)"
        }
        if ubiquityContainerURL != nil {
            return "iCloud Drive Container aktiv"
        }
        if isICloudAccountActive {
            return "iCloud angemeldet (Wähle Zielordner)"
        }
        return "Nicht mit iCloud angemeldet"
    }

    // MARK: - Custom Folder Management

    func setCustomFolder(_ url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: [.isDirectoryKey, .localizedNameKey],
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            updateCustomFolderName()
        } catch {
            errorMessage = "Ordner-Zugriff fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func clearCustomFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        customFolderName = nil
    }

    private func updateCustomFolderName() {
        if let url = customFolderURL {
            customFolderName = url.lastPathComponent
        } else {
            customFolderName = nil
        }
    }

    // MARK: - Synchronization

    func sync(progress: @escaping @Sendable (String) -> Void) async -> SyncResult {
        guard let targetURL = resolvedSyncURL else {
            let res = SyncResult(uploaded: 0, downloaded: 0, errors: ["Kein iCloud-Zielordner verfügbar. Bitte wähle einen Ordner in iCloud Drive."])
            errorMessage = res.errors.first
            return res
        }

        isSyncing = true
        errorMessage = nil
        let isSecurityScoped = customFolderURL != nil
        if isSecurityScoped {
            _ = targetURL.startAccessingSecurityScopedResource()
        }

        defer {
            if isSecurityScoped {
                targetURL.stopAccessingSecurityScopedResource()
            }
            isSyncing = false
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [localRoot] in
                var result = SyncResult()
                let fm = FileManager.default

                do {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                } catch {
                    result.errors.append("Konnte iCloud-Ordner nicht erstellen: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = result.errors.first
                        continuation.resume(returning: result)
                    }
                    return
                }

                progress("Lese lokale und iCloud-Dateien…")

                // Map local items
                let localItems = self.scanDirectory(at: localRoot)
                let cloudItems = self.scanDirectory(at: targetURL)

                // 1. Upload local -> iCloud
                for (rel, localDate) in localItems {
                    let sourceURL = localRoot.appendingPathComponent(rel)
                    let destURL = targetURL.appendingPathComponent(rel)
                    let cloudDate = cloudItems[rel]

                    if cloudDate == nil || localDate > (cloudDate! + 2.0) {
                        do {
                            let parentDir = destURL.deletingLastPathComponent()
                            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                            if fm.fileExists(atPath: destURL.path) {
                                try fm.removeItem(at: destURL)
                            }
                            try fm.copyItem(at: sourceURL, to: destURL)
                            result.uploaded += 1
                            progress("↑ \(rel)")
                        } catch {
                            result.errors.append("iCloud Upload \(rel): \(error.localizedDescription)")
                        }
                    }
                }

                // 2. Download iCloud -> local
                for (rel, cloudDate) in cloudItems {
                    let sourceURL = targetURL.appendingPathComponent(rel)
                    let destURL = localRoot.appendingPathComponent(rel)
                    let localDate = localItems[rel]

                    if localDate == nil || cloudDate > (localDate! + 2.0) {
                        do {
                            let parentDir = destURL.deletingLastPathComponent()
                            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                            if fm.fileExists(atPath: destURL.path) {
                                try fm.removeItem(at: destURL)
                            }
                            try fm.copyItem(at: sourceURL, to: destURL)
                            result.downloaded += 1
                            progress("↓ \(rel)")
                        } catch {
                            result.errors.append("iCloud Download \(rel): \(error.localizedDescription)")
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.lastSynced = Date()
                    UserDefaults.standard.set(self.lastSynced, forKey: self.lastSyncedKey)
                    self.lastSummary = result.summary
                    if let err = result.errors.first {
                        self.errorMessage = err
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Scanning Helper

    private nonisolated func scanDirectory(at root: URL) -> [String: Date] {
        var map: [String: Date] = [:]
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isPackageKey]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return map }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            guard !filename.hasPrefix("."), filename != ".DS_Store" else { continue }

            let isBundle = filename.hasSuffix(".enote") ||
                           filename.hasSuffix(".epap") ||
                           filename.hasSuffix(".ewb") ||
                           filename.hasSuffix(".emm")

            if isBundle {
                enumerator.skipDescendants()
            }

            guard let res = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = res.isDirectory ?? false
            if isDir && !isBundle { continue }

            let mod = res.contentModificationDate ?? Date()
            let rel = String(fileURL.path.dropFirst(root.path.count + 1))
            map[rel] = mod
        }

        return map
    }
}
