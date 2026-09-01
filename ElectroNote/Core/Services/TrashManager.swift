import Foundation

struct TrashItem: Identifiable, Codable {
    let id: UUID
    let originalRelPath: String  // relative to rootURL
    let name: String
    let trashedAt: Date
}

final class TrashManager: ObservableObject {
    static let shared = TrashManager()

    @Published private(set) var items: [TrashItem] = []

    private var rootURL: URL?
    private var trashURL: URL? { rootURL?.appendingPathComponent(".trash", isDirectory: true) }
    private var manifestURL: URL? { trashURL?.appendingPathComponent(".manifest.json") }

    func configure(rootURL: URL) {
        self.rootURL = rootURL
        if let url = trashURL {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        loadManifest()
    }

    func moveToTrash(item: DocumentItem, rootURL: URL) throws {
        let relPath = String(item.path.path.dropFirst(rootURL.path.count + 1))
        let uuid = UUID()
        guard let trashURL else { throw CocoaError(.fileWriteUnknown) }
        let destDir = trashURL.appendingPathComponent(uuid.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destItem = destDir.appendingPathComponent(item.path.lastPathComponent)
        try FileManager.default.moveItem(at: item.path, to: destItem)
        items.append(TrashItem(id: uuid, originalRelPath: relPath, name: item.name, trashedAt: Date()))
        saveManifest()
    }

    func restore(_ trashItem: TrashItem) throws {
        guard let rootURL, let trashURL else { return }
        let srcDir  = trashURL.appendingPathComponent(trashItem.id.uuidString)
        let lastComponent = (trashItem.originalRelPath as NSString).lastPathComponent
        let src = srcDir.appendingPathComponent(lastComponent)
        let relParent = (trashItem.originalRelPath as NSString).deletingLastPathComponent
        let destParent = relParent.isEmpty ? rootURL : rootURL.appendingPathComponent(relParent)
        try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
        var dest = destParent.appendingPathComponent(lastComponent)
        // Avoid collision
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (lastComponent as NSString).deletingPathExtension
            let ext  = (lastComponent as NSString).pathExtension
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            dest = destParent.appendingPathComponent(newName)
            counter += 1
        }
        try FileManager.default.moveItem(at: src, to: dest)
        try? FileManager.default.removeItem(at: srcDir)
        items.removeAll { $0.id == trashItem.id }
        saveManifest()
    }

    func deletePermanently(_ trashItem: TrashItem) throws {
        if let trashURL {
            try? FileManager.default.removeItem(at: trashURL.appendingPathComponent(trashItem.id.uuidString))
        }
        items.removeAll { $0.id == trashItem.id }
        saveManifest()
    }

    func emptyTrash() {
        guard let trashURL else { return }
        items.forEach { try? FileManager.default.removeItem(at: trashURL.appendingPathComponent($0.id.uuidString)) }
        items.removeAll()
        saveManifest()
    }

    private func loadManifest() {
        guard let url = manifestURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TrashItem].self, from: data) else { return }
        items = decoded
    }

    private func saveManifest() {
        guard let url = manifestURL, let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
