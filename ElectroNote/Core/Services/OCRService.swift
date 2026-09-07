import UIKit
import PDFKit
import Vision

final class OCRService {

    static let shared = OCRService()

    /// Extracts text from a PDF page directly if vector text exists, or falls back to OCR for scanned pages.
    func extractText(from page: PDFPage, fallbackImage: UIImage? = nil) async -> String {
        // 1. If vector text is already present in the PDF, return it immediately (100% exact & instant)
        if let vectorText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !vectorText.isEmpty {
            return vectorText
        }

        // 2. If it's a scanned PDF page, run Apple Vision OCR on the rendered image
        if let img = fallbackImage {
            return (try? await recognizeText(in: img)) ?? ""
        }
        return ""
    }

    /// Convenience method to extract text from a UIImage.
    func extractText(from image: UIImage) async -> String {
        return (try? await recognizeText(in: image)) ?? ""
    }

    /// Performs offline OCR on a UIImage using Apple's Vision framework (Neural Engine).
    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                // Sort lines by vertical position (top to bottom, Vision coords have origin at bottom-left)
                let sortedObservations = observations.sorted { obs1, obs2 in
                    if abs(obs1.boundingBox.midY - obs2.boundingBox.midY) > 0.015 {
                        return obs1.boundingBox.midY > obs2.boundingBox.midY
                    }
                    return obs1.boundingBox.minX < obs2.boundingBox.minX
                }

                let lines = sortedObservations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
