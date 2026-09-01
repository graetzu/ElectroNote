import Foundation

struct SyncResult {
    var uploaded   = 0
    var downloaded = 0
    var errors: [String] = []

    var summary: String {
        "↑ \(uploaded)  ↓ \(downloaded)" + (errors.isEmpty ? "" : "  ⚠️ \(errors.count)")
    }
}

final class SyncEngine {
    let client: WebDAVClient
    let localRoot: URL
    let remoteFolder = "ElectroNote"

    init(client: WebDAVClient, localRoot: URL) {
        self.client    = client
        self.localRoot = localRoot
    }

    func sync(progress: @escaping @Sendable (String) -> Void) async -> SyncResult {
        var result = SyncResult()
        do {
            // Ensure remote root directory exists
            try await client.mkcol(path: remoteFolder)

            // Remote file inventory
            progress("Nextcloud wird gelesen…")
            let remoteFiles = try await client.propfind(path: remoteFolder, depth: "infinity")
            var remoteMap: [String: Date] = [:]
            let prefix = remoteFolder + "/"
            for f in remoteFiles where !f.isDirectory {
                let rel = f.davPath.hasPrefix(prefix) ? String(f.davPath.dropFirst(prefix.count)) : f.davPath
                remoteMap[rel] = f.lastModified
            }

            // Local file inventory
            let localMap = walkLocal()

            // Upload: local-only or locally newer
            for (relPath, localDate) in localMap {
                let remoteDate = remoteMap[relPath]
                if remoteDate == nil || localDate > remoteDate! + 2 {
                    do {
                        try await uploadFile(relPath: relPath)
                        result.uploaded += 1
                        progress("↑ \(relPath)")
                    } catch {
                        result.errors.append("Upload \(relPath): \(error.localizedDescription)")
                    }
                }
            }

            // Download: remote-only or remotely newer
            for (relPath, remoteDate) in remoteMap {
                let localDate = localMap[relPath]
                if localDate == nil || remoteDate > localDate! + 2 {
                    do {
                        try await downloadFile(relPath: relPath, remoteDate: remoteDate)
                        result.downloaded += 1
                        progress("↓ \(relPath)")
                    } catch {
                        result.errors.append("Download \(relPath): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            result.errors.append(error.localizedDescription)
        }
        return result
    }

    // MARK: - Local walk

    private func walkLocal() -> [String: Date] {
        var map: [String: Date] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: localRoot, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return map }

        for case let url as URL in enumerator {
            guard let res = try? url.resourceValues(forKeys: Set(keys)),
                  !(res.isDirectory ?? false),
                  let mod = res.contentModificationDate
            else { continue }
            let rel = String(url.path.dropFirst(localRoot.path.count + 1))
            map[rel] = mod
        }
        return map
    }

    // MARK: - Upload / Download

    private func uploadFile(relPath: String) async throws {
        let remotePath = "\(remoteFolder)/\(relPath)"
        try await client.ensureDirectories(for: remotePath)
        let data = try Data(contentsOf: localRoot.appendingPathComponent(relPath))
        try await client.put(path: remotePath, data: data)
    }

    private func downloadFile(relPath: String, remoteDate: Date) async throws {
        let data     = try await client.get(path: "\(remoteFolder)/\(relPath)")
        let localURL = localRoot.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: localURL, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: remoteDate],
                                               ofItemAtPath: localURL.path)
    }
}
