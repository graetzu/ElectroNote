import PencilKit
import Foundation

final class PDFAnnotationStore {
    private let annotationsURL: URL

    init(pdfURL: URL) {
        annotationsURL = pdfURL.appendingPathExtension("annotations")
        try? FileManager.default.createDirectory(at: annotationsURL, withIntermediateDirectories: true)
    }

    func loadDrawing(for pageIndex: Int) -> PKDrawing {
        guard let data = try? Data(contentsOf: drawingURL(for: pageIndex)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing, for pageIndex: Int) {
        try? drawing.dataRepresentation().write(to: drawingURL(for: pageIndex), options: .atomic)
    }

    private func drawingURL(for pageIndex: Int) -> URL {
        annotationsURL.appendingPathComponent("page_\(pageIndex).pkdrawing")
    }
}
