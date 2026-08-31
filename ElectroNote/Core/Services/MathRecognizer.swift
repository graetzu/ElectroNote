import Vision
import UIKit
import PencilKit

// Recognises handwritten mathematical expressions via VNRecognizeTextRequest.
final class MathRecognizer {

    func recognise(drawing: PKDrawing, canvasSize: CGSize) async -> String? {
        guard !drawing.strokes.isEmpty else { return nil }

        let image = render(drawing: drawing, size: canvasSize)
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel      = .accurate
        request.recognitionLanguages  = ["de-DE", "en-US"]
        request.usesLanguageCorrection = false  // maths: don't "correct" symbols

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        let strings = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return strings.joined(separator: " ")
    }

    // MARK: - Private

    private func render(drawing: PKDrawing, size: CGSize) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2           // higher res → better OCR
        format.opaque = true

        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(bounds)

            // Fit drawing into bounds
            let db = drawing.bounds
            guard db.width > 0, db.height > 0 else { return }
            let scale = min(bounds.width / db.width, bounds.height / db.height) * 0.85
            let tx = (bounds.width  - db.width  * scale) / 2 - db.minX * scale
            let ty = (bounds.height - db.height * scale) / 2 - db.minY * scale

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: tx, y: ty)
            ctx.cgContext.scaleBy(x: scale, y: scale)

            let ink = drawing.image(from: db, scale: 2)
            ink.draw(in: db)
            ctx.cgContext.restoreGState()
        }
    }
}
