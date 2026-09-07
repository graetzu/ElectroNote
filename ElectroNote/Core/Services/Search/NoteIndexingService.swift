import Foundation
import UIKit
import PencilKit
import Vision
import PDFKit

final class NoteIndexingService {
    static let shared = NoteIndexingService()

    private let db = NoteSearchDatabase.shared
    private var debouncedTasks: [URL: Task<Void, Never>] = [:]
    private let queue = DispatchQueue(label: "de.graetz.electronote.indexing", qos: .utility)
    private var isSweepingCatalog = false

    private init() {}

    // MARK: - Debounced Live Indexing (During or after user writing)

    func scheduleDebouncedIndex(
        for store: NotebookDocumentStore,
        drawing: PKDrawing,
        document: NotebookDocument,
        delay: TimeInterval = 2.5
    ) {
        let url = store.noteURL
        debouncedTasks[url]?.cancel()
        debouncedTasks[url] = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            await self.indexNotebook(store: store, url: url, drawing: drawing, document: document)
        }
    }

    // MARK: - Direct Notebook Indexing

    func indexNotebook(
        store: NotebookDocumentStore,
        url: URL,
        drawing: PKDrawing,
        document: NotebookDocument
    ) async {
        let docPath = url.path
        let docName = url.deletingPathExtension().lastPathComponent
        var activeChunkIds = Set<String>()

        // 1. Index Handwriting (Spatial Tiling)
        let hwChunkIds = await indexHandwriting(docPath: docPath, docName: docName, drawing: drawing)
        activeChunkIds.formUnion(hwChunkIds)

        // 2. Index Sticky Notes
        for note in document.stickyNotes {
            let chunkId = "sticky_\(note.id.uuidString)"
            activeChunkIds.insert(chunkId)
            let trimmedText = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty { continue }

            let hash = "\(trimmedText.hashValue)_\(Int(note.x))_\(Int(note.y))"
            let storedHash = await db.getChunkHash(docPath: docPath, chunkId: chunkId)
            if storedHash != hash {
                let entry = IndexEntry(
                    contentType: .stickyNote,
                    textContent: trimmedText,
                    canvasRect: CGRect(x: note.x, y: note.y, width: 220, height: 220),
                    chunkId: chunkId
                )
                await db.updateChunk(
                    docPath: docPath,
                    docName: docName,
                    chunkId: chunkId,
                    chunkHash: hash,
                    entries: [entry]
                )
            }
        }

        // 3. Index Inserted Content (Typed Text Items, Converted Handwriting, Scans, ClipArts, Photos)
        for img in document.insertedImages {
            let chunkId = "img_\(img.id.uuidString)"
            activeChunkIds.insert(chunkId)

            var textToIndex: String? = nil
            var contentType: SearchContentType = .text

            if let typed = img.textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty {
                // Getippter Text oder umgewandelte Handschrift
                textToIndex = typed
                contentType = .text
            } else if let scanText = img.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !scanText.isEmpty {
                // Importierte Dokumentenseite / Scan mit vorhandenem OCR-Text
                textToIndex = scanText
                contentType = .scan
            } else if img.mediaType == nil || img.isDocumentPage == true {
                // Bild/Scan ohne vorheriges OCR: Text im Hintergrund extrahieren
                let imgURL = store.imageURL(filename: img.filename)
                if let data = try? Data(contentsOf: imgURL), let uiImg = UIImage(data: data) {
                    let recognized = autoreleasepool {
                        runVisionOCR(on: uiImg, tileRect: CGRect(x: img.startX, y: img.startY, width: img.width, height: img.height))
                    }
                    let combined = recognized.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !combined.isEmpty {
                        textToIndex = combined
                        contentType = .scan
                    }
                }
            }

            if let text = textToIndex {
                let hash = "\(text.hashValue)_\(Int(img.startX))_\(Int(img.startY))"
                let storedHash = await db.getChunkHash(docPath: docPath, chunkId: chunkId)
                if storedHash != hash {
                    let entry = IndexEntry(
                        contentType: contentType,
                        textContent: text,
                        canvasRect: CGRect(x: img.startX, y: img.startY, width: img.width, height: img.height),
                        chunkId: chunkId
                    )
                    await db.updateChunk(
                        docPath: docPath,
                        docName: docName,
                        chunkId: chunkId,
                        chunkHash: hash,
                        entries: [entry]
                    )
                }
            }
        }

        // 4. Index Bookmarks
        for bm in document.bookmarks {
            let chunkId = "bm_\(bm.id.uuidString)"
            activeChunkIds.insert(chunkId)
            let trimmed = bm.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let hash = "\(trimmed.hashValue)_\(Int(bm.y))"
            let storedHash = await db.getChunkHash(docPath: docPath, chunkId: chunkId)
            if storedHash != hash {
                let entry = IndexEntry(
                    contentType: .bookmark,
                    textContent: trimmed,
                    canvasRect: CGRect(x: 0, y: bm.y, width: NotebookDocument.pageWidth, height: 40),
                    chunkId: chunkId
                )
                await db.updateChunk(
                    docPath: docPath,
                    docName: docName,
                    chunkId: chunkId,
                    chunkHash: hash,
                    entries: [entry]
                )
            }
        }

        // 5. Cleanup removed chunks (e.g. deleted sticky notes, erased handwriting tiles)
        await db.removeMissingChunks(docPath: docPath, validChunkIds: activeChunkIds)

        // 6. Record timestamp
        let now = Date().timeIntervalSince1970
        await db.setDocumentIndexed(docPath: docPath, docType: "enote", lastModified: now)
    }

    // MARK: - Spatial Handwriting Tiling

    private func indexHandwriting(docPath: String, docName: String, drawing: PKDrawing) async -> Set<String> {
        var activeHwChunks = Set<String>()
        guard !drawing.strokes.isEmpty else { return activeHwChunks }

        let bounds = drawing.bounds
        guard !bounds.isNull && bounds.width > 0 && bounds.height > 0 else { return activeHwChunks }

        let tileSize: CGFloat = 900
        let overlap: CGFloat  = 60
        let step: CGFloat     = tileSize - overlap

        let startX = max(0, floor(bounds.minX / step) * step)
        let startY = max(0, floor(bounds.minY / step) * step)
        let endX   = bounds.maxX
        let endY   = bounds.maxY

        var y = startY
        while y < endY {
            var x = startX
            while x < endX {
                let tileRect = CGRect(x: x, y: y, width: tileSize, height: tileSize)
                let strokes = drawing.strokes.filter { $0.renderBounds.intersects(tileRect) }

                if !strokes.isEmpty {
                    let chunkId = "hw_\(Int(x))_\(Int(y))"
                    activeHwChunks.insert(chunkId)

                    let hash = computeStrokeHash(strokes)
                    let storedHash = await db.getChunkHash(docPath: docPath, chunkId: chunkId)

                    if storedHash != hash {
                        // Tile is dirty -> process in autoreleasepool to release bitmap immediately
                        let observations: [(text: String, rect: CGRect)] = autoreleasepool {
                            guard let img = renderTileImage(from: drawing, tileRect: tileRect) else { return [] }
                            return runVisionOCR(on: img, tileRect: tileRect)
                        }

                        let entries = observations.map { obs in
                            IndexEntry(
                                contentType: .handwriting,
                                textContent: obs.text,
                                canvasRect: obs.rect,
                                chunkId: chunkId
                            )
                        }

                        await db.updateChunk(
                            docPath: docPath,
                            docName: docName,
                            chunkId: chunkId,
                            chunkHash: hash,
                            entries: entries
                        )

                        await Task.yield()
                    }
                }
                x += step
            }
            y += step
        }

        return activeHwChunks
    }

    // MARK: - Standalone PDF Document Indexing

    func indexStandalonePDF(url: URL) async {
        guard let pdf = PDFDocument(url: url) else { return }
        let docPath = url.path
        let docName = url.deletingPathExtension().lastPathComponent
        var activeChunkIds = Set<String>()

        for pageIdx in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIdx) else { continue }
            let chunkId = "pdf_page_\(pageIdx)"
            activeChunkIds.insert(chunkId)

            var pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.isEmpty {
                // Scanned PDF page fallback OCR
                let b = page.bounds(for: .cropBox)
                let renderer = UIGraphicsImageRenderer(size: b.size)
                let pageImg = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: b.size))
                    ctx.cgContext.translateBy(x: 0.0, y: b.size.height)
                    ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                    page.draw(with: .cropBox, to: ctx.cgContext)
                }
                let obs = autoreleasepool {
                    runVisionOCR(on: pageImg, tileRect: b)
                }
                pageText = obs.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if !pageText.isEmpty {
                let hash = "\(pageText.hashValue)"
                let storedHash = await db.getChunkHash(docPath: docPath, chunkId: chunkId)
                if storedHash != hash {
                    let entry = IndexEntry(
                        contentType: .pdf,
                        textContent: pageText,
                        canvasRect: CGRect(x: 0, y: CGFloat(pageIdx * 842), width: 595, height: 842),
                        pageIndex: pageIdx,
                        chunkId: chunkId
                    )
                    await db.updateChunk(
                        docPath: docPath,
                        docName: docName,
                        chunkId: chunkId,
                        chunkHash: hash,
                        entries: [entry]
                    )
                }
            }
            await Task.yield()
        }

        await db.removeMissingChunks(docPath: docPath, validChunkIds: activeChunkIds)
        await db.setDocumentIndexed(docPath: docPath, docType: "pdf", lastModified: Date().timeIntervalSince1970)
    }

    // MARK: - Tile Image Rendering (High Contrast Template)

    private func renderTileImage(from drawing: PKDrawing, tileRect: CGRect) -> UIImage? {
        let scale: CGFloat = 1.5
        let ink = drawing.image(from: tileRect, scale: scale)
        guard ink.size.width > 0 && ink.size.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: ink.size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: ink.size))
            let tinted = ink.withRenderingMode(.alwaysTemplate)
            UIColor.black.set()
            tinted.draw(in: CGRect(origin: .zero, size: ink.size))
        }
    }

    // MARK: - Vision OCR (Synchronous in background worker)

    private func runVisionOCR(on image: UIImage, tileRect: CGRect) -> [(text: String, rect: CGRect)] {
        guard let cgImage = image.cgImage else { return [] }
        var results: [(text: String, rect: CGRect)] = []

        let request = VNRecognizeTextRequest { req, err in
            guard err == nil, let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      !candidate.isEmpty else { continue }
                let box = obs.boundingBox
                let x = tileRect.origin.x + box.origin.x * tileRect.width
                let y = tileRect.origin.y + (1.0 - box.origin.y - box.height) * tileRect.height
                let w = box.width * tileRect.width
                let h = box.height * tileRect.height
                results.append((text: candidate, rect: CGRect(x: x, y: y, width: w, height: h)))
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return results
    }

    // MARK: - Stroke Hashing for Dirty Tracking

    private func computeStrokeHash(_ strokes: [PKStroke]) -> String {
        var hasher = Hasher()
        hasher.combine(strokes.count)
        for stroke in strokes {
            let b = stroke.renderBounds
            hasher.combine(Int(b.origin.x * 10))
            hasher.combine(Int(b.origin.y * 10))
            hasher.combine(Int(b.width * 10))
            hasher.combine(Int(b.height * 10))
            hasher.combine(stroke.path.count)
        }
        return String(hasher.finalize())
    }

    // MARK: - Background Catalog Sweep

    func startIndexingAllDocuments(fileService: FileServiceProtocol) {
        guard !isSweepingCatalog else { return }
        isSweepingCatalog = true

        Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            let allDocs = fileService.listAllDocuments()

            for item in allDocs {
                let docURL = item.path
                let docPath = docURL.path

                let lastModifiedOnDisk: Double
                if let attrs = try? FileManager.default.attributesOfItem(atPath: docPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    lastModifiedOnDisk = modDate.timeIntervalSince1970
                } else {
                    lastModifiedOnDisk = 0
                }

                let lastIndexed = await self.db.getDocumentLastIndexed(docPath: docPath) ?? 0

                if item.type == .note {
                    // If note document was modified since last index or has never been indexed
                    if lastModifiedOnDisk > lastIndexed || lastIndexed == 0 {
                        let store = NotebookDocumentStore(noteURL: docURL)
                        let drawing = store.loadDrawing()
                        let document = store.loadDocument()
                        await self.indexNotebook(store: store, url: docURL, drawing: drawing, document: document)
                    }
                } else if item.type == .pdf {
                    // If standalone PDF was modified or never indexed
                    if lastModifiedOnDisk > lastIndexed || lastIndexed == 0 {
                        await self.indexStandalonePDF(url: docURL)
                    }
                }

                await Task.yield()
            }
            self.isSweepingCatalog = false
        }
    }
}
