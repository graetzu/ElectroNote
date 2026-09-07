import Foundation
import PencilKit
import UIKit
import PDFKit

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
        if !FileManager.default.fileExists(atPath: drawingURL.path) {
            try? PKDrawing().dataRepresentation().write(to: drawingURL, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: documentURL.path) {
            if let data = try? JSONEncoder().encode(NotebookDocument()) {
                try? data.write(to: documentURL, options: .atomic)
            }
        }
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

    // MARK: - Appending Content from External Files

    @discardableResult
    func appendPDF(from sourceURL: URL) async throws -> InsertedPDF {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let pdfURL: URL
        do {
            pdfURL = try await DocumentConverter.shared.convertToPDF(sourceURL: sourceURL)
        } catch {
            if sourceURL.pathExtension.lowercased() == "pdf" {
                pdfURL = sourceURL
            } else {
                throw error
            }
        }

        let pdfAccessing = (pdfURL != sourceURL) ? pdfURL.startAccessingSecurityScopedResource() : false
        defer { if pdfAccessing { pdfURL.stopAccessingSecurityScopedResource() } }

        let filename = try copyPDF(from: pdfURL)
        let storedURL = self.pdfURL(filename: filename)
        guard let pdf = PDFDocument(url: storedURL), pdf.pageCount > 0 else {
            throw NSError(domain: "ElectroNote", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDF-Dokument konnte nicht geladen werden."])
        }

        var doc = loadDocument()
        let drawing = loadDrawing()

        let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        let pdfBottom     = doc.insertedPDFs.last?.endY ?? 0
        let imgBottom     = doc.insertedImages.last.map { $0.startY + $0.height } ?? 0
        let maxContent    = max(drawingBottom, pdfBottom, imgBottom)
        let docWidth: CGFloat = NotebookDocument.pageWidth
        let a4PageH       = docWidth * 1.41421356
        let startY        = maxContent <= 10 ? 0 : (ceil(maxContent / a4PageH) * a4PageH)

        var y = startY
        var heights: [CGFloat] = []

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let b = page.bounds(for: .cropBox)
            let ratio = (b.width > 0 && b.height > 0) ? (b.height / b.width) : 1.41421356
            let h = (abs(ratio - 1.41421356) < 0.05) ? a4PageH : (docWidth * ratio)
            heights.append(h)

            let targetSize = CGSize(width: max(docWidth, 100) * 2, height: max(h, 100) * 2)
            let thumb = page.thumbnail(of: targetSize, for: .cropBox)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let whiteThumb = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: targetSize))
                thumb.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            let pageText = await OCRService.shared.extractText(from: page, fallbackImage: whiteThumb)
            if let imgFilename = try? saveImage(whiteThumb) {
                let imgEntry = InsertedImage(
                    id: UUID(),
                    filename: imgFilename,
                    startX: 0,
                    startY: y,
                    width: docWidth,
                    height: h,
                    extractedText: pageText.isEmpty ? nil : pageText,
                    isDocumentPage: true
                )
                doc.insertedImages.append(imgEntry)
            }
            y += h
        }

        let needed = y + NotebookDocument.initialHeight * 0.3
        if needed > doc.documentHeight {
            doc.documentHeight = needed
        }

        let entry = InsertedPDF(id: UUID(), filename: filename, startY: startY, pageHeights: heights)
        doc.insertedPDFs.append(entry)
        saveDocument(doc)
        return entry
    }

    @discardableResult
    func appendImage(_ image: UIImage) async throws -> InsertedImage {
        guard image.size.width > 0 && image.size.height > 0 else {
            throw NSError(domain: "ElectroNote", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiges Bild."])
        }
        let filename = try saveImage(image)
        let extractedText = await OCRService.shared.extractText(from: image)

        var doc = loadDocument()
        let drawing = loadDrawing()

        let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        let pdfBottom     = doc.insertedPDFs.last?.endY ?? 0
        let imgBottom     = doc.insertedImages.last.map { $0.startY + $0.height } ?? 0
        let startY        = max(drawingBottom, pdfBottom, imgBottom) + 40

        let maxW: CGFloat = NotebookDocument.pageWidth - 40
        let ratio = image.size.height / max(image.size.width, 1)
        let w = min(maxW, image.size.width)
        let h = w * ratio
        let startX: CGFloat = 20

        let needed = startY + h + NotebookDocument.initialHeight * 0.3
        if needed > doc.documentHeight {
            doc.documentHeight = needed
        }

        let entry = InsertedImage(
            id: UUID(),
            filename: filename,
            startX: startX,
            startY: startY,
            width: w,
            height: h,
            extractedText: extractedText.isEmpty ? nil : extractedText
        )
        doc.insertedImages.append(entry)
        saveDocument(doc)
        return entry
    }
}
