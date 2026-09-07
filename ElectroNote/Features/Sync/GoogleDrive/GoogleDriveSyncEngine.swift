import Foundation
import SwiftUI

@MainActor
final class GoogleDriveSyncEngine: ObservableObject {

    @Published var credentials: GoogleDriveCredentials?
    @Published var isSyncing = false
    @Published var lastSynced: Date?
    @Published var lastSummary: String?
    @Published var progressMessage: String?
    @Published var errorMessage: String?

    let localRoot: URL
    private let lastSyncedKey = "gdrive_last_synced"

    init(localRoot: URL = FileService.defaultRootURL) {
        self.localRoot = localRoot
        self.credentials = GoogleDriveCredentials.load()
        self.lastSynced = UserDefaults.standard.object(forKey: lastSyncedKey) as? Date
    }

    var isConnected: Bool {
        credentials != nil && !(credentials?.accessToken.isEmpty ?? true)
    }

    // MARK: - Login / Logout

    func login(accessToken: String, refreshToken: String? = nil, email: String? = nil, name: String? = nil) async {
        var creds = GoogleDriveCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userEmail: email,
            userName: name,
            folderId: nil
        )
        creds.save()
        self.credentials = creds

        // Fetch user profile if email/name not set
        if email == nil || name == nil {
            let client = GoogleDriveClient(credentials: creds)
            if let info = try? await client.getUserInfo() {
                creds.userName = info.name
                creds.userEmail = info.email
                creds.save()
                self.credentials = creds
            }
        }
    }

    func logout() {
        GoogleDriveCredentials.logout()
        credentials = nil
        lastSynced = nil
        lastSummary = nil
        errorMessage = nil
        progressMessage = nil
    }

    // MARK: - Synchronization

    func sync(progress: @escaping @Sendable (String) -> Void) async -> SyncResult {
        guard let creds = credentials else {
            let res = SyncResult(uploaded: 0, downloaded: 0, errors: ["Nicht mit Google Drive angemeldet."])
            self.errorMessage = res.errors.first
            return res
        }

        isSyncing = true
        errorMessage = nil
        progressMessage = "Verbinde mit Google Drive…"

        let client = GoogleDriveClient(credentials: creds)

        do {
            // 1. Ensure remote root 'ElectroNote' folder exists
            let rootFolderId = try await client.findOrCreateFolder(name: "ElectroNote")
            if creds.folderId != rootFolderId {
                var updated = creds
                updated.folderId = rootFolderId
                updated.save()
                self.credentials = updated
            }

            var result = SyncResult()

            // 2. Fetch remote items in ElectroNote folder
            progress("Lese Google Drive Dateien…")
            let remoteFiles = try await client.listFiles(inFolderId: rootFolderId)
            var remoteMap: [String: GoogleDriveFile] = [:]
            for f in remoteFiles {
                remoteMap[f.name] = f
            }

            // 3. Scan local files
            let localItems = walkLocalDirect()

            // 4. Upload local -> Google Drive
            for (name, localDate) in localItems {
                let localFile = localRoot.appendingPathComponent(name)
                let remote = remoteMap[name]

                if remote == nil || localDate > (remote!.lastModifiedDate + 2.0) {
                    do {
                        let isDir = (try? localFile.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        if isDir {
                            // Synchronize directory/bundle (e.g. .enote, .epap)
                            let bundleFolderId = try await client.findOrCreateFolder(name: name, parentId: rootFolderId)
                            let subFiles = (try? FileManager.default.contentsOfDirectory(at: localFile, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
                            for sf in subFiles {
                                if let data = try? Data(contentsOf: sf) {
                                    _ = try await client.uploadFile(
                                        name: sf.lastPathComponent,
                                        data: data,
                                        mimeType: mimeType(for: sf.pathExtension),
                                        folderId: bundleFolderId
                                    )
                                }
                            }
                        } else {
                            if let data = try? Data(contentsOf: localFile) {
                                _ = try await client.uploadFile(
                                    name: name,
                                    data: data,
                                    mimeType: mimeType(for: localFile.pathExtension),
                                    folderId: rootFolderId,
                                    existingFileId: remote?.id
                                )
                            }
                        }
                        result.uploaded += 1
                        progress("↑ \(name)")
                    } catch {
                        result.errors.append("Google Drive Upload \(name): \(error.localizedDescription)")
                    }
                }
            }

            // 5. Download Google Drive -> Local
            for (name, remoteFile) in remoteMap {
                let localFile = localRoot.appendingPathComponent(name)
                let localDate = localItems[name]

                if localDate == nil || remoteFile.lastModifiedDate > (localDate! + 2.0) {
                    do {
                        if remoteFile.isFolder {
                            try FileManager.default.createDirectory(at: localFile, withIntermediateDirectories: true)
                            let remoteSubFiles = try await client.listFiles(inFolderId: remoteFile.id)
                            for sf in remoteSubFiles where !sf.isFolder {
                                let subData = try await client.downloadFile(fileId: sf.id)
                                let destSub = localFile.appendingPathComponent(sf.name)
                                try subData.write(to: destSub, options: .atomic)
                            }
                        } else {
                            let data = try await client.downloadFile(fileId: remoteFile.id)
                            try data.write(to: localFile, options: .atomic)
                        }
                        result.downloaded += 1
                        progress("↓ \(name)")
                    } catch {
                        result.errors.append("Google Drive Download \(name): \(error.localizedDescription)")
                    }
                }
            }

            lastSynced = Date()
            UserDefaults.standard.set(lastSynced, forKey: lastSyncedKey)
            lastSummary = result.summary
            if let err = result.errors.first {
                errorMessage = err
            }
            isSyncing = false
            progressMessage = nil
            return result

        } catch {
            isSyncing = false
            progressMessage = nil
            errorMessage = error.localizedDescription
            return SyncResult(uploaded: 0, downloaded: 0, errors: [error.localizedDescription])
        }
    }

    // MARK: - Helpers

    private func walkLocalDirect() -> [String: Date] {
        var map: [String: Date] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: localRoot, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return map }

        for fileURL in contents {
            let name = fileURL.lastPathComponent
            guard !name.hasPrefix("."), name != ".DS_Store" else { continue }
            if let res = try? fileURL.resourceValues(forKeys: Set(keys)),
               let mod = res.contentModificationDate {
                map[name] = mod
            }
        }
        return map
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "pkdrawing": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}
