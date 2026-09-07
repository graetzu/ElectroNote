import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct IncomingFileInfo: Identifiable {
    let id = UUID()
    let localURL: URL
    let originalFilename: String
    let baseName: String
    let fileExtension: String
    let fileSize: Int64
    let isPDF: Bool
    let isImage: Bool
    let isOfficeOrDoc: Bool

    var formattedSize: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: fileSize)
    }

    var fileTypeDisplayName: String {
        if isPDF { return "PDF-Dokument" }
        if isImage { return "Bilddatei (\(fileExtension.uppercased()))" }
        if ["docx", "doc"].contains(fileExtension) { return "Word-Dokument" }
        if ["xlsx", "xls"].contains(fileExtension) { return "Excel-Tabelle" }
        if ["pptx", "ppt"].contains(fileExtension) { return "PowerPoint-Präsentation" }
        if ["txt", "rtf"].contains(fileExtension) { return "Textdokument" }
        return "\(fileExtension.uppercased())-Datei"
    }

    var iconName: String {
        if isPDF { return "doc.richtext.fill" }
        if isImage { return "photo.fill" }
        if ["docx", "doc", "txt", "rtf"].contains(fileExtension) { return "doc.text.fill" }
        if ["xlsx", "xls"].contains(fileExtension) { return "tablecells.fill" }
        if ["pptx", "ppt"].contains(fileExtension) { return "rectangle.fill.on.rectangle.fill" }
        return "doc.fill"
    }

    var iconColor: Color {
        if isPDF { return .red }
        if isImage { return .purple }
        if ["docx", "doc"].contains(fileExtension) { return .blue }
        if ["xlsx", "xls"].contains(fileExtension) { return .green }
        if ["pptx", "ppt"].contains(fileExtension) { return .orange }
        return .accentColor
    }
}

@MainActor
final class ExternalFileImportManager: ObservableObject {
    static let shared = ExternalFileImportManager()

    @Published var incomingFile: IncomingFileInfo?
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private init() {}

    func handleIncomingURL(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let incomingDir = fileManager.temporaryDirectory.appendingPathComponent("IncomingSharedFiles", isDirectory: true)
        try? fileManager.createDirectory(at: incomingDir, withIntermediateDirectories: true)

        // Clean up temporary shared files older than 30 minutes
        cleanOldIncomingFiles(in: incomingDir)

        let origFilename = url.lastPathComponent
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        let uniqueDest = incomingDir.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(origFilename)")
        try? fileManager.removeItem(at: uniqueDest)

        do {
            try fileManager.copyItem(at: url, to: uniqueDest)

            let attrs = try fileManager.attributesOfItem(atPath: uniqueDest.path)
            let size = attrs[.size] as? Int64 ?? 0

            let isPDF = ext == "pdf"
            let isImage = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"].contains(ext)
            let isOfficeOrDoc = DocumentConverter.supportedTypes.contains { utType in
                utType.preferredFilenameExtension?.lowercased() == ext
            } || ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "rtf"].contains(ext)

            self.incomingFile = IncomingFileInfo(
                localURL: uniqueDest,
                originalFilename: origFilename,
                baseName: base,
                fileExtension: ext,
                fileSize: size,
                isPDF: isPDF,
                isImage: isImage,
                isOfficeOrDoc: isOfficeOrDoc
            )
        } catch {
            self.errorMessage = "Konnte Datei nicht empfangen: \(error.localizedDescription)"
        }
    }

    private func cleanOldIncomingFiles(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-1800) // 30 minutes
        for file in files {
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let creationDate = attrs[.creationDate] as? Date,
               creationDate < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    func dismiss() {
        // Do not immediately delete file.localURL, as asynchronous import/conversion
        // tasks in open notebooks or store workers may still be actively reading it.
        incomingFile = nil
        isProcessing = false
        statusMessage = nil
        errorMessage = nil
    }
}
