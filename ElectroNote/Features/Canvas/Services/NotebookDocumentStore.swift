import Foundation
import PencilKit
import UIKit

final class NotebookDocumentStore {
    let noteURL: URL

    private var documentURL: URL { noteURL.appendingPathComponent("document.json") }
    private var drawingURL:  URL { noteURL.appendingPathComponent("drawing.pkdrawing") }
    private var pdfsFolder:  URL { noteURL.appendingPathComponent("pdfs") }
    private var imagesFolder: URL { noteURL.appendingPathComponent("images") }

    init(noteURL: URL) {
        self.noteURL = noteURL
        try? FileManager.default.createDirectory(at: pdfsFolder,    withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesFolder,  withIntermediateDirectories: true)
    }

    // MARK: - Document

    func loadDocument() -> NotebookDocument {
        guard let data = try? Data(contentsOf: documentURL),
              let doc  = try? JSONDecoder().decode(NotebookDocument.self, from: data)
        else { return NotebookDocument() }
        return doc
    }

    func saveDocument(_ doc: NotebookDocument) {
        if let data = try? JSONEncoder().encode(doc) {
            try? data.write(to: documentURL, options: .atomic)
        }
    }

    // MARK: - Drawing

    func loadDrawing() -> PKDrawing {
        guard let data    = try? Data(contentsOf: drawingURL),
              let drawing = try? PKDrawing(data: data)
        else { return PKDrawing() }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing) {
        try? drawing.dataRepresentation().write(to: drawingURL, options: .atomic)
    }

    // MARK: - PDF

    func copyPDF(from url: URL) throws -> String {
        let filename = UUID().uuidString + ".pdf"
        try FileManager.default.copyItem(at: url, to: pdfsFolder.appendingPathComponent(filename))
        return filename
    }

    func pdfURL(filename: String) -> URL {
        pdfsFolder.appendingPathComponent(filename)
    }

    // MARK: - Images (plots)

    func saveImage(_ image: UIImage) throws -> String {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let filename = UUID().uuidString + ".png"
        try data.write(to: imagesFolder.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func imageURL(filename: String) -> URL {
        imagesFolder.appendingPathComponent(filename)
    }
}
