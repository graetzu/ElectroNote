import Foundation

protocol FileServiceProtocol: AnyObject {
    var rootURL: URL { get }
    func listItems(at url: URL) -> [DocumentItem]
    func listAllDocuments() -> [DocumentItem]
    func listAllFolders() -> [URL]
    func displayPath(for item: DocumentItem) -> String
    func createFolder(named name: String, at url: URL) throws -> DocumentItem
    func createNote(named name: String, at url: URL) throws -> DocumentItem
    func createDocument(named name: String, type: DocumentType, at url: URL) throws -> DocumentItem
    func rename(item: DocumentItem, to newName: String) throws -> DocumentItem
    func move(item: DocumentItem, to destination: URL) throws -> DocumentItem
    func delete(item: DocumentItem) throws
    func importPDF(from sourceURL: URL, to destinationURL: URL) throws -> DocumentItem
}

final class FileService: FileServiceProtocol {

    static var defaultRootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("ElectroNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    let rootURL: URL

    init() {
        self.rootURL = Self.defaultRootURL
    }

    func listItems(at url: URL) -> [DocumentItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { fileURL -> DocumentItem? in
            guard let res = try? fileURL.resourceValues(forKeys: Set(keys)) else { return nil }
            let isDir     = res.isDirectory ?? false
            let modified  = res.contentModificationDate ?? Date()
            let filename  = fileURL.lastPathComponent

            let type: DocumentItem.ItemType
            let displayName: String

            if isDir && filename.hasSuffix(".enote") {
                type = .note
                displayName = String(filename.dropLast(".enote".count))
            } else if isDir && filename.hasSuffix(".epap") {
                type = .pap
                displayName = String(filename.dropLast(".epap".count))
            } else if isDir && filename.hasSuffix(".ewb") {
                type = .whiteboard
                displayName = String(filename.dropLast(".ewb".count))
            } else if isDir && filename.hasSuffix(".emm") {
                type = .mindmap
                displayName = String(filename.dropLast(".emm".count))
            } else if isDir {
                type = .folder
                displayName = filename
            } else if fileURL.pathExtension.lowercased() == "pdf" {
                type = .pdf
                displayName = String(filename.dropLast(".pdf".count))
            } else {
                return nil
            }

            return DocumentItem(
                id: UUID(),
                name: displayName,
                path: fileURL,
                type: type,
                modifiedAt: modified,
                syncStatus: .local
            )
        }
        .sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func listAllDocuments() -> [DocumentItem] {
        var results: [DocumentItem] = []
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        func scan(directory: URL) {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: .skipsHiddenFiles
            ) else { return }

            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(".") || filename.lowercased() == ".trash" {
                    continue
                }
                guard let res = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                let isDir = res.isDirectory ?? false
                let modified = res.contentModificationDate ?? Date()

                if isDir && filename.hasSuffix(".enote") {
                    let name = String(filename.dropLast(".enote".count))
                    results.append(DocumentItem(id: UUID(), name: name, path: fileURL, type: .note, modifiedAt: modified, syncStatus: .local))
                } else if isDir && filename.hasSuffix(".epap") {
                    let name = String(filename.dropLast(".epap".count))
                    results.append(DocumentItem(id: UUID(), name: name, path: fileURL, type: .pap, modifiedAt: modified, syncStatus: .local))
                } else if isDir && filename.hasSuffix(".ewb") {
                    let name = String(filename.dropLast(".ewb".count))
                    results.append(DocumentItem(id: UUID(), name: name, path: fileURL, type: .whiteboard, modifiedAt: modified, syncStatus: .local))
                } else if isDir && filename.hasSuffix(".emm") {
                    let name = String(filename.dropLast(".emm".count))
                    results.append(DocumentItem(id: UUID(), name: name, path: fileURL, type: .mindmap, modifiedAt: modified, syncStatus: .local))
                } else if !isDir && fileURL.pathExtension.lowercased() == "pdf" {
                    let name = String(filename.dropLast(".pdf".count))
                    results.append(DocumentItem(id: UUID(), name: name, path: fileURL, type: .pdf, modifiedAt: modified, syncStatus: .local))
                } else if isDir && !filename.hasSuffix(".annotations") {
                    scan(directory: fileURL)
                }
            }
        }

        scan(directory: rootURL)
        return results.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func listAllFolders() -> [URL] {
        var folders: [URL] = [rootURL]
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey]

        func scan(directory: URL) {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: .skipsHiddenFiles
            ) else { return }

            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(".") || filename.lowercased() == ".trash" { continue }
                guard let res = try? fileURL.resourceValues(forKeys: Set(keys)),
                      res.isDirectory ?? false else { continue }
                if filename.hasSuffix(".enote") || filename.hasSuffix(".epap") ||
                   filename.hasSuffix(".ewb") || filename.hasSuffix(".emm") ||
                   filename.hasSuffix(".annotations") {
                    continue
                }
                folders.append(fileURL)
                scan(directory: fileURL)
            }
        }

        scan(directory: rootURL)
        return folders
    }

    func displayPath(for item: DocumentItem) -> String {
        let rootPath = rootURL.path
        let parentPath = item.path.deletingLastPathComponent().path
        if parentPath == rootPath || !parentPath.hasPrefix(rootPath) {
            return "Hauptordner"
        }
        let rel = parentPath.dropFirst(rootPath.count)
        let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : String(rel)
        return cleaned.replacingOccurrences(of: "/", with: " > ")
    }

    func createFolder(named name: String, at url: URL) throws -> DocumentItem {
        let dest = uniqueURL(base: name, ext: nil, isDir: true, in: url)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        return makeItem(at: dest, name: dest.lastPathComponent, type: .folder)
    }

    func createNote(named name: String, at url: URL) throws -> DocumentItem {
        try createDocument(named: name, type: .notebook, at: url)
    }

    func createDocument(named name: String, type: DocumentType, at url: URL) throws -> DocumentItem {
        let ext  = type.fileExtension
        let dest = uniqueURL(base: name, ext: ext, isDir: true, in: url)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        let metadata = NoteMetadata(title: name, createdAt: Date())
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: dest.appendingPathComponent("metadata.json"))

        if type == .pap {
            let initialDoc = DiagramDocumentDTO(name: name, type: "pap")
            let store = DiagramDocumentStore(folderURL: dest)
            store.save(initialDoc)
        } else if type == .mindmap {
            let initialDoc = DiagramDocumentDTO(name: name, type: "mindmap")
            let store = DiagramDocumentStore(folderURL: dest)
            store.save(initialDoc)
        }

        return makeItem(at: dest, name: name, type: type.itemType)
    }

    func rename(item: DocumentItem, to newName: String) throws -> DocumentItem {
        let suffix: String
        switch item.type {
        case .note:       suffix = ".enote"
        case .pap:        suffix = ".epap"
        case .whiteboard: suffix = ".ewb"
        case .mindmap:    suffix = ".emm"
        case .pdf:        suffix = ".pdf"
        case .folder:     suffix = ""
        }
        let dest = item.path.deletingLastPathComponent()
            .appendingPathComponent(newName + suffix)
        try FileManager.default.moveItem(at: item.path, to: dest)
        var updated = item
        updated.name = newName
        updated.path = dest
        return updated
    }

    func move(item: DocumentItem, to destination: URL) throws -> DocumentItem {
        let dest = destination.appendingPathComponent(item.path.lastPathComponent)
        try FileManager.default.moveItem(at: item.path, to: dest)
        var updated = item
        updated.path = dest
        return updated
    }

    func delete(item: DocumentItem) throws {
        try FileManager.default.removeItem(at: item.path)
    }

    func importPDF(from sourceURL: URL, to destinationURL: URL) throws -> DocumentItem {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let dest = uniqueURL(base: baseName, ext: "pdf", isDir: false, in: destinationURL)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return makeItem(at: dest, name: dest.deletingPathExtension().lastPathComponent, type: .pdf)
    }

    // MARK: - Private

    private func uniqueURL(base: String, ext: String?, isDir: Bool, in url: URL) -> URL {
        func candidate(_ suffix: String) -> URL {
            let filename = ext.map { "\(suffix).\($0)" } ?? suffix
            return url.appendingPathComponent(filename, isDirectory: isDir)
        }
        var result = candidate(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = candidate("\(base) \(counter)")
            counter += 1
        }
        return result
    }

    private func makeItem(at url: URL, name: String, type: DocumentItem.ItemType) -> DocumentItem {
        DocumentItem(id: UUID(), name: name, path: url, type: type,
                     modifiedAt: Date(), syncStatus: .local)
    }
}

// MARK: - Supporting types

struct NoteMetadata: Codable {
    var title: String
    var createdAt: Date
    var tags: [String] = []
}
