import Foundation
import PencilKit
import UIKit
import PDFKit

final class NotebookDocumentStore {
    let noteURL: URL

    private var documentURL: URL { noteURL.appendingPathComponent("document.json") }
    private var drawingURL:  URL { noteURL.appendingPathComponent("drawing.pkdrawing") }
    private var drawingJsonURL: URL { noteURL.appendingPathComponent("drawing.json") }
    private var pdfsFolder:   URL { noteURL.appendingPathComponent("pdfs") }
    private var imagesFolder: URL { noteURL.appendingPathComponent("images") }
    private var videosFolder: URL { noteURL.appendingPathComponent("videos") }

    init(noteURL: URL) {
        self.noteURL = noteURL
        try? FileManager.default.createDirectory(at: pdfsFolder,    withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesFolder,  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosFolder,  withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: drawingURL.path) && !FileManager.default.fileExists(atPath: drawingJsonURL.path) {
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
        let pkExists = FileManager.default.fileExists(atPath: drawingURL.path)
        let jsonExists = FileManager.default.fileExists(atPath: drawingJsonURL.path)

        if jsonExists {
            let jsonDate = (try? drawingJsonURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let pkDate = (try? drawingURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

            if !pkExists || jsonDate > pkDate.addingTimeInterval(1.0) {
                if let imported = PencilKitBridge.loadDrawing(from: drawingJsonURL) {
                    try? imported.dataRepresentation().write(to: drawingURL, options: .atomic)
                    return imported
                }
            }
        }

        guard let data    = try? Data(contentsOf: drawingURL),
              let drawing = try? PKDrawing(data: data)
        else { return PKDrawing() }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing) {
        // 1. Save Apple binary cache
        try? drawing.dataRepresentation().write(to: drawingURL, options: .atomic)
        // 2. Export portable JSON for Android
        PencilKitBridge.saveDrawing(drawing, to: drawingJsonURL)
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

    // MARK: - Videos

    func copyVideo(from url: URL) throws -> String {
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let filename = UUID().uuidString + "." + ext
        let dest = videosFolder.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: url, to: dest)
        return filename
    }

    func saveVideoData(_ data: Data, fileExtension: String = "mp4") throws -> String {
        let filename = UUID().uuidString + "." + fileExtension
        let dest = videosFolder.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
        return filename
    }

    func videoURL(filename: String) -> URL {
        videosFolder.appendingPathComponent(filename)
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
            let b = page.bounds(for: .cropBox).width > 0 ? page.bounds(for: .cropBox) : page.bounds(for: .mediaBox)
            let rot = (page.rotation % 360 + 360) % 360
            let isLandscape = (rot == 90 || rot == 270)
            let unscaledW = max(isLandscape ? b.height : b.width, 1)
            let unscaledH = max(isLandscape ? b.width : b.height, 1)
            let ratio = unscaledH / unscaledW
            let h = (abs(ratio - 1.41421356) < 0.05) ? a4PageH : (docWidth * ratio)
            heights.append(h)

            let pageImg = autoreleasepool {
                PDFPageRenderer.render(page: page, width: docWidth, height: h)
            }

            if let imgFilename = try? saveImage(pageImg) {
                let imgEntry = InsertedImage(
                    id: UUID(),
                    filename: imgFilename,
                    startX: 0,
                    startY: y,
                    width: docWidth,
                    height: h,
                    extractedText: nil,
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

        // Schedule background OCR indexing without blocking UI
        let finalDoc = doc
        Task.detached(priority: .utility) {
            await NoteIndexingService.shared.indexNotebook(store: self, url: self.noteURL, drawing: drawing, document: finalDoc)
        }

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

// MARK: - Vector PDF Page Renderer

enum PDFPageRenderer {
    static func render(page: PDFPage, width: CGFloat, height: CGFloat, scale: CGFloat? = nil) -> UIImage {
        let actualScale = scale ?? max(UIScreen.main.scale, 2.0)
        let pixelSize = CGSize(
            width: max(round(width * actualScale), 100),
            height: max(round(height * actualScale), 100)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0 // Render 1:1 at exact pixel dimensions
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixelSize))

            let cg = ctx.cgContext
            cg.saveGState()

            // Flip UIKit top-left coordinates to CoreGraphics bottom-left coordinates
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: 1.0, y: -1.0)

            let box = page.bounds(for: .cropBox).width > 0 ? page.bounds(for: .cropBox) : page.bounds(for: .mediaBox)
            let rot = (page.rotation % 360 + 360) % 360
            let isLandscape = (rot == 90 || rot == 270)
            let unscaledW = max(isLandscape ? box.height : box.width, 1)
            let unscaledH = max(isLandscape ? box.width : box.height, 1)

            let scaleX = pixelSize.width / max(unscaledW, 1)
            let scaleY = pixelSize.height / max(unscaledH, 1)
            cg.scaleBy(x: scaleX, y: scaleY)

            switch rot {
            case 90:
                cg.rotate(by: -.pi / 2)
                cg.translateBy(x: -box.width, y: 0)
            case 180:
                cg.rotate(by: -.pi)
                cg.translateBy(x: -box.width, y: -box.height)
            case 270:
                cg.rotate(by: -3 * .pi / 2)
                cg.translateBy(x: 0, y: -box.height)
            default:
                break
            }

            cg.translateBy(x: -box.origin.x, y: -box.origin.y)
            page.draw(with: .cropBox, to: cg)
            cg.restoreGState()
        }
    }
}

