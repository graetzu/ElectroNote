import UIKit
import WebKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class DocumentConverter: NSObject {

    static let shared = DocumentConverter()

    /// Supported document import UTTypes
    static let supportedTypes: [UTType] = [
        .pdf,
        .plainText,
        .rtf,
        .text,
        .spreadsheet,
        .presentation,
        UTType("com.microsoft.word.doc") ?? .data,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("com.microsoft.excel.xls") ?? .data,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("com.microsoft.powerpoint.ppt") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        UTType("com.apple.iwork.pages.pages") ?? .data,
        UTType("com.apple.iwork.numbers.numbers") ?? .data,
        UTType("com.apple.iwork.keynote.key") ?? .data
    ]

    /// Converts any Office (Word/Excel/PowerPoint), iWork, RTF, TXT or PDF document into a PDF URL.
    func convertToPDF(sourceURL: URL) async throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "pdf" {
            return sourceURL
        }

        // Try RTF / PlainText conversion via NSAttributedString first if applicable
        if ext == "rtf" || ext == "txt" || ext == "text" {
            if let pdfURL = try? convertTextOrRTFToPDF(sourceURL: sourceURL) {
                return pdfURL
            }
        }

        // Convert Office (.docx, .doc, .xlsx, .xls, .pptx, .ppt, etc.) via headless WKWebView
        return try await convertViaWebKit(sourceURL: sourceURL)
    }

    private func convertTextOrRTFToPDF(sourceURL: URL) throws -> URL {
        let isRTF = sourceURL.pathExtension.lowercased() == "rtf"
        let docType: NSAttributedString.DocumentType = isRTF ? .rtf : .plain
        let attrString = try NSAttributedString(
            url: sourceURL,
            options: [.documentType: docType],
            documentAttributes: nil
        )

        let printFormatter = UISimpleTextPrintFormatter(attributedText: attrString)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)

        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let printable = CGRect(x: 36, y: 36, width: pageWidth - 72, height: pageHeight - 72)
        let paper = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, paper, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        try pdfData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func convertViaWebKit(sourceURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
            let tempTarget = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).pdf")

            final class NavigationDelegateHolder: NSObject, WKNavigationDelegate {
                let targetURL: URL
                let continuation: CheckedContinuation<URL, Error>
                var didFinish = false

                init(targetURL: URL, continuation: CheckedContinuation<URL, Error>) {
                    self.targetURL = targetURL
                    self.continuation = continuation
                }

                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                    guard !didFinish else { return }
                    didFinish = true

                    // Allow WebKit layout to settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        let config = WKPDFConfiguration()
                        webView.createPDF(configuration: config) { result in
                            switch result {
                            case .success(let data):
                                do {
                                    try data.write(to: self.targetURL)
                                    self.continuation.resume(returning: self.targetURL)
                                } catch {
                                    self.continuation.resume(throwing: error)
                                }
                            case .failure(let err):
                                self.continuation.resume(throwing: err)
                            }
                        }
                    }
                }

                func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                    guard !didFinish else { return }
                    didFinish = true
                    continuation.resume(throwing: error)
                }

                func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
                    guard !didFinish else { return }
                    didFinish = true
                    continuation.resume(throwing: error)
                }
            }

            let holder = NavigationDelegateHolder(targetURL: tempTarget, continuation: continuation)
            objc_setAssociatedObject(webView, "holder", holder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.navigationDelegate = holder

            let accessURL = sourceURL.deletingLastPathComponent()
            webView.loadFileURL(sourceURL, allowingReadAccessTo: accessURL)
        }
    }
}
