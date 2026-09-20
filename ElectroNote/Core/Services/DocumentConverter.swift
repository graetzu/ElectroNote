import UIKit
import PDFKit
import UniformTypeIdentifiers
import WebKit
import zlib

// MARK: - Subclassed PDFPrintPageRenderer (Overrides read-only paperRect / printableRect)

final class PDFPrintPageRenderer: UIPrintPageRenderer {
    private let customPaperRect: CGRect
    private let customPrintableRect: CGRect

    init(paperRect: CGRect, printableRect: CGRect) {
        self.customPaperRect = paperRect
        self.customPrintableRect = printableRect
        super.init()
    }

    override var paperRect: CGRect { customPaperRect }
    override var printableRect: CGRect { customPrintableRect }
}

// MARK: - DocumentConverter

@MainActor
final class DocumentConverter: NSObject {

    static let shared = DocumentConverter()

    /// Supported document import UTTypes
    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .rtf, .text, .html]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        if let docxId = UTType("org.openxmlformats.wordprocessingml.document"), !types.contains(docxId) { types.append(docxId) }
        if let docId = UTType("com.microsoft.word.doc"), !types.contains(docId) { types.append(docId) }
        return types
    }()

    /// Converts any supported document (.docx, .doc, .rtf, .txt, .html, .pdf) into a temporary PDF URL.
    func convertToPDF(sourceURL: URL) async throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "pdf" {
            return sourceURL
        }

        // Tier 1: Try WebKit native conversion first for .docx, .doc, .rtf, .html, .txt
        // WKWebView natively renders Microsoft Word (.docx, .doc), RTF, and HTML with full layout fidelity
        if ["docx", "doc", "html", "htm", "rtf", "txt", "text"].contains(ext) {
            do {
                let converter = WebKitDocumentToPDFConverter()
                return try await converter.convert(fileURL: sourceURL)
            } catch {
                #if DEBUG
                print("[DocumentConverter] WebKit conversion failed or timed out: \(error). Trying native fallback engine...")
                #endif
            }
        }

        // Tier 2: OpenXML Parser for .docx
        if ext == "docx" {
            do {
                return try convertDocxToPDFviaXML(sourceURL: sourceURL)
            } catch {
                #if DEBUG
                print("[DocumentConverter] OpenXML conversion failed: \(error). Falling back to text extraction...")
                #endif
                return try convertDocxTextFallbackToPDF(sourceURL: sourceURL)
            }
        }

        // Tier 3: RTF & TXT native fallback
        if ext == "rtf" || ext == "txt" || ext == "text" {
            return try convertTextOrRTFToPDF(sourceURL: sourceURL)
        }

        // Tier 4: HTML fallback
        if ext == "html" || ext == "htm" {
            return try convertHTMLToPDF(sourceURL: sourceURL)
        }

        if ext == "doc" {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Das .doc-Dokument konnte nicht geladen werden. Bitte speichere es als .docx oder .pdf."]
            )
        }

        throw NSError(
            domain: "DocumentConverter",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Das Format .\(ext.uppercased()) wird nicht direkt unterstützt. Bitte exportiere die Datei vorher als PDF oder Word (.docx)."]
        )
    }

    /// Extracts clean, structured plain text from a Word (.docx) document for editable note insertion.
    func extractTextFromDocx(sourceURL: URL) throws -> String {
        let fileData = try Data(contentsOf: sourceURL)
        var entries = Self.unzipEntriesCentralDirectory(from: fileData)
        if entries["word/document.xml"] == nil {
            let localEntries = Self.unzipEntriesLocalHeaders(from: fileData)
            for (k, v) in localEntries {
                entries[k] = v
            }
        }

        guard let docXML = entries["word/document.xml"] else {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Ungültige Word-Datei (.docx): 'word/document.xml' fehlt."]
            )
        }

        let parser = XMLParser(data: docXML)
        let handler = DocxXMLHandler(imageMap: [:])
        parser.delegate = handler
        parser.parse()
        return handler.plainText
    }

    // MARK: - DOCX Conversion (Native ZIP + OpenXML to HTML + PDF)

    private func convertDocxToPDFviaXML(sourceURL: URL) throws -> URL {
        let fileData = try Data(contentsOf: sourceURL)
        var entries = Self.unzipEntriesCentralDirectory(from: fileData)
        if entries["word/document.xml"] == nil {
            let localEntries = Self.unzipEntriesLocalHeaders(from: fileData)
            for (k, v) in localEntries {
                entries[k] = v
            }
        }

        guard let docXML = entries["word/document.xml"] else {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Ungültige Word-Datei (.docx): Die Datei 'word/document.xml' konnte nicht gefunden werden."]
            )
        }

        // Parse relationship targets for embedded images
        var imageMap: [String: Data] = [:]
        if let relsData = entries["word/_rels/document.xml.rels"],
           let relsStr = String(data: relsData, encoding: .utf8) {
            let pattern = "<Relationship[^>]*Id=\"([^\"]+)\"[^>]*Target=\"([^\"]+)\""
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(relsStr.startIndex..<relsStr.endIndex, in: relsStr)
                let matches = regex.matches(in: relsStr, range: range)
                for match in matches {
                    if match.numberOfRanges == 3,
                       let idRange = Range(match.range(at: 1), in: relsStr),
                       let targetRange = Range(match.range(at: 2), in: relsStr) {
                        let rId = String(relsStr[idRange])
                        let target = String(relsStr[targetRange])
                        let cleanTarget = target.replacingOccurrences(of: "\\", with: "/")
                        let fullPath = cleanTarget.hasPrefix("word/") ? cleanTarget : "word/\(cleanTarget)"
                        if let imgData = entries[fullPath.lowercased()] ?? entries[cleanTarget.lowercased()] {
                            imageMap[rId] = imgData
                        }
                    }
                }
            }
        }

        let parser = XMLParser(data: docXML)
        let handler = DocxXMLHandler(imageMap: imageMap)
        parser.delegate = handler
        parser.parse()

        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 11pt;
            color: #1a1a1a;
            line-height: 1.45;
            padding: 0;
            margin: 0;
        }
        h1 { font-size: 18pt; font-weight: bold; margin-top: 14pt; margin-bottom: 6pt; color: #111; }
        h2 { font-size: 15pt; font-weight: bold; margin-top: 12pt; margin-bottom: 5pt; color: #222; }
        h3 { font-size: 13pt; font-weight: 600; margin-top: 10pt; margin-bottom: 4pt; color: #333; }
        p { margin: 0 0 6pt 0; }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 10pt 0;
            border: 1px solid #c0c0c0;
        }
        td, th {
            border: 1px solid #c0c0c0;
            padding: 5pt 8pt;
            vertical-align: top;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        </style>
        </head>
        <body>
        \(handler.html)
        </body>
        </html>
        """

        return try renderHTMLToPDF(htmlString)
    }

    private func convertDocxTextFallbackToPDF(sourceURL: URL) throws -> URL {
        let text = (try? extractTextFromDocx(sourceURL: sourceURL)) ?? (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "DocumentConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein lesbarer Text im Dokument gefunden."])
        }

        let paragraphs = text.components(separatedBy: "\n\n")
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br/>"))</p>" }
            .joined(separator: "\n")

        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, sans-serif; font-size: 11pt; line-height: 1.5; color: #111; }
        p { margin-bottom: 8pt; }
        </style>
        </head>
        <body>\(paragraphs)</body>
        </html>
        """
        return try renderHTMLToPDF(html)
    }

    // MARK: - HTML Conversion

    private func convertHTMLToPDF(sourceURL: URL) throws -> URL {
        let htmlString = try String(contentsOf: sourceURL, encoding: .utf8)
        return try renderHTMLToPDF(htmlString)
    }

    private func renderHTMLToPDF(_ htmlString: String) throws -> URL {
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlString)
        return try Self.renderPrintFormatterToPDF(formatter)
    }

    // MARK: - Plain Text & RTF Conversion

    private func convertTextOrRTFToPDF(sourceURL: URL) throws -> URL {
        let isRTF = sourceURL.pathExtension.lowercased() == "rtf"
        if isRTF {
            let attrString = try NSAttributedString(
                url: sourceURL,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            let printFormatter = UISimpleTextPrintFormatter(attributedText: attrString)
            return try Self.renderPrintFormatterToPDF(printFormatter)
        } else {
            let text = try String(contentsOf: sourceURL, encoding: .utf8)
            let printFormatter = UISimpleTextPrintFormatter(text: text)
            printFormatter.font = UIFont.systemFont(ofSize: 11)
            return try Self.renderPrintFormatterToPDF(printFormatter)
        }
    }

    // MARK: - Shared PDF Renderer

    static func renderPrintFormatterToPDF(
        _ formatter: UIPrintFormatter,
        pageSize: CGSize = CGSize(width: 595.2, height: 841.8),
        margin: CGFloat = 36.0
    ) throws -> URL {
        let paper = CGRect(origin: .zero, size: pageSize)
        let printable = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        let renderer = PDFPrintPageRenderer(paperRect: paper, printableRect: printable)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let totalPages = renderer.numberOfPages
        guard totalPages > 0 else {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "PDF-Generierung ergab 0 Seiten."]
            )
        }

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: totalPages))

        for pageIndex in 0..<totalPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: printable)
        }
        UIGraphicsEndPDFContext()

        guard pdfData.length > 0 else {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "PDF-Generierung hat keine Daten erzeugt."]
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        try pdfData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - WebKit Document Converter

    @MainActor
    private final class WebKitDocumentToPDFConverter: NSObject, WKNavigationDelegate {
        private var webView: WKWebView?
        private var continuation: CheckedContinuation<URL, Error>?
        private var tempDirectory: URL?
        private var timeoutTask: Task<Void, Never>?

        func convert(fileURL: URL) async throws -> URL {
            return try await withCheckedThrowingContinuation { cont in
                self.continuation = cont

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WKDocConvert_\(UUID().uuidString)")
                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let safeURL = tempDir.appendingPathComponent(fileURL.lastPathComponent)
                    try FileManager.default.copyItem(at: fileURL, to: safeURL)
                    self.tempDirectory = tempDir

                    let config = WKWebViewConfiguration()
                    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
                    let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 595.2, height: 841.8), configuration: config)
                    wv.navigationDelegate = self
                    self.webView = wv

                    self.timeoutTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 12_000_000_000)
                        guard let self = self, let c = self.continuation else { return }
                        self.continuation = nil
                        self.cleanup()
                        c.resume(throwing: NSError(
                            domain: "DocumentConverter",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "WebKit-Konvertierung Zeitüberschreitung."]
                        ))
                    }

                    wv.loadFileURL(safeURL, allowingReadAccessTo: tempDir)
                } catch {
                    self.cleanup()
                    cont.resume(throwing: error)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            timeoutTask?.cancel()
            timeoutTask = nil

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.renderPDF(webView: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            timeoutTask?.cancel()
            timeoutTask = nil
            let c = continuation
            continuation = nil
            cleanup()
            c?.resume(throwing: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            timeoutTask?.cancel()
            timeoutTask = nil
            let c = continuation
            continuation = nil
            cleanup()
            c?.resume(throwing: error)
        }

        private func renderPDF(webView: WKWebView) {
            guard let cont = continuation else { return }
            self.continuation = nil

            do {
                let formatter = webView.viewPrintFormatter()
                let pdfURL = try DocumentConverter.renderPrintFormatterToPDF(formatter)
                self.cleanup()
                cont.resume(returning: pdfURL)
                return
            } catch {
                #if DEBUG
                print("[WebKitDocumentToPDFConverter] viewPrintFormatter failed: \(error). Falling back to webView.createPDF...")
                #endif
            }

            webView.createPDF { [weak self] result in
                guard let self = self else { return }
                defer { self.cleanup() }
                switch result {
                case .success(let pdfData):
                    do {
                        let pdfURL = try self.saveOrPaginatePDFData(pdfData)
                        cont.resume(returning: pdfURL)
                    } catch {
                        cont.resume(throwing: error)
                    }
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }
        }

        private func saveOrPaginatePDFData(_ pdfData: Data) throws -> URL {
            guard let doc = PDFDocument(data: pdfData), doc.pageCount > 0 else {
                throw NSError(domain: "DocumentConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiges PDF von WebKit erzeugt."])
            }

            let firstPage = doc.page(at: 0)
            let bounds = firstPage?.bounds(for: .mediaBox) ?? .zero
            let a4Height: CGFloat = 841.8
            let a4Width: CGFloat = 595.2

            if doc.pageCount > 1 || bounds.height <= a4Height * 1.4 {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).pdf")
                try pdfData.write(to: tempURL, options: .atomic)
                return tempURL
            }

            let totalHeight = bounds.height
            let totalWidth = bounds.width > 0 ? bounds.width : a4Width
            let scale = a4Width / totalWidth
            let sliceHeightInDoc = a4Height / scale

            let pageSlices = Int(ceil(totalHeight / sliceHeightInDoc))
            let splitData = NSMutableData()
            let paper = CGRect(x: 0, y: 0, width: a4Width, height: a4Height)
            UIGraphicsBeginPDFContextToData(splitData, paper, nil)

            for pageIdx in 0..<pageSlices {
                UIGraphicsBeginPDFPage()
                guard let ctx = UIGraphicsGetCurrentContext() else { continue }
                ctx.saveGState()

                ctx.translateBy(x: 0, y: a4Height)
                ctx.scaleBy(x: 1.0, y: -1.0)

                let yOffset = CGFloat(pageIdx) * sliceHeightInDoc
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: 0, y: -(totalHeight - (yOffset + sliceHeightInDoc)))

                firstPage?.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            UIGraphicsEndPDFContext()

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).pdf")
            try splitData.write(to: tempURL, options: .atomic)
            return tempURL
        }

        private func cleanup() {
            webView?.navigationDelegate = nil
            webView?.stopLoading()
            webView = nil
            if let dir = tempDirectory {
                try? FileManager.default.removeItem(at: dir)
                tempDirectory = nil
            }
        }
    }


    // MARK: - ZIP Unpacker (zlib Raw Deflate)

    private static func decompressRawDeflate(data: Data, uncompressedSize: Int) -> Data? {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var decompressed = Data(count: uncompressedSize)
        let status = data.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> Int32 in
            stream.next_in = UnsafeMutablePointer(mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)

            return decompressed.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) -> Int32 in
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(uncompressedSize)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard status == Z_STREAM_END || status == Z_OK else { return nil }
        decompressed.count = Int(stream.total_out)
        return decompressed
    }

    // MARK: - ZIP Unpacker (Central Directory + Fallback Local Headers)

    private static func unzipEntriesCentralDirectory(from zipData: Data) -> [String: Data] {
        var results: [String: Data] = [:]
        let count = zipData.count
        guard count >= 22 else { return results }

        // Find End of Central Directory Record (0x06054b50) scanning backwards from end
        var eocdOffset = -1
        let searchStart = max(0, count - 65557)
        for i in stride(from: count - 22, through: searchStart, by: -1) {
            let sig = zipData.subdata(in: i..<i+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            if sig == 0x06054b50 {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0 else { return results }

        let cdTotalEntries = Int(zipData.subdata(in: eocdOffset+10..<eocdOffset+12).withUnsafeBytes { $0.load(as: UInt16.self) })
        let cdOffset = Int(zipData.subdata(in: eocdOffset+16..<eocdOffset+20).withUnsafeBytes { $0.load(as: UInt32.self) })

        var offset = cdOffset
        for _ in 0..<cdTotalEntries {
            guard offset + 46 <= count else { break }
            let sig = zipData.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard sig == 0x02014b50 else { break }

            let method = zipData.subdata(in: offset+10..<offset+12).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compSize = Int(zipData.subdata(in: offset+20..<offset+24).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompSize = Int(zipData.subdata(in: offset+24..<offset+28).withUnsafeBytes { $0.load(as: UInt32.self) })
            let nameLen = Int(zipData.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraLen = Int(zipData.subdata(in: offset+30..<offset+32).withUnsafeBytes { $0.load(as: UInt16.self) })
            let commentLen = Int(zipData.subdata(in: offset+32..<offset+34).withUnsafeBytes { $0.load(as: UInt16.self) })
            let localHeaderOffset = Int(zipData.subdata(in: offset+42..<offset+46).withUnsafeBytes { $0.load(as: UInt32.self) })

            let nameData = zipData.subdata(in: offset+46..<offset+46+nameLen)
            if let rawName = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) {
                let normalizedName = rawName.replacingOccurrences(of: "\\", with: "/").lowercased()

                if localHeaderOffset + 30 <= count {
                    let localNameLen = Int(zipData.subdata(in: localHeaderOffset+26..<localHeaderOffset+28).withUnsafeBytes { $0.load(as: UInt16.self) })
                    let localExtraLen = Int(zipData.subdata(in: localHeaderOffset+28..<localHeaderOffset+30).withUnsafeBytes { $0.load(as: UInt16.self) })
                    let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen

                    if dataStart + compSize <= count {
                        let fileData = zipData.subdata(in: dataStart..<dataStart+compSize)
                        if method == 0 {
                            results[normalizedName] = fileData
                        } else if method == 8 {
                            if let decomp = decompressRawDeflate(data: fileData, uncompressedSize: uncompSize) {
                                results[normalizedName] = decomp
                            }
                        }
                    }
                }
            }

            offset += 46 + nameLen + extraLen + commentLen
        }

        return results
    }

    private static func unzipEntriesLocalHeaders(from zipData: Data) -> [String: Data] {
        var results: [String: Data] = [:]
        var offset = 0
        let count = zipData.count

        while offset + 30 <= count {
            let sig = zipData.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard sig == 0x04034b50 else {
                offset += 1
                continue
            }

            let method = zipData.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compSize = Int(zipData.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompSize = Int(zipData.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) })
            let nameLen = Int(zipData.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraLen = Int(zipData.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })

            let nameStart = offset + 30
            guard nameStart + nameLen <= count else { break }
            let nameData = zipData.subdata(in: nameStart..<nameStart + nameLen)
            guard let rawName = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) else {
                offset = nameStart + nameLen + extraLen + compSize
                continue
            }
            let normalizedName = rawName.replacingOccurrences(of: "\\", with: "/").lowercased()

            let dataStart = nameStart + nameLen + extraLen
            if dataStart + compSize <= count && compSize > 0 {
                let fileData = zipData.subdata(in: dataStart..<dataStart + compSize)
                if method == 0 {
                    results[normalizedName] = fileData
                } else if method == 8 {
                    if let decomp = decompressRawDeflate(data: fileData, uncompressedSize: uncompSize) {
                        results[normalizedName] = decomp
                    }
                }
            }

            offset = dataStart + max(0, compSize)
        }
        return results
    }
}

// MARK: - DOCX XML Parser to HTML

private final class DocxXMLHandler: NSObject, XMLParserDelegate {
    var html = ""
    var plainText = ""
    private let imageMap: [String: Data]
    private var inParagraph = false
    private var inRun = false
    private var inText = false
    private var inTable = false
    private var inRow = false
    private var inCell = false
    private var isBold = false
    private var isItalic = false
    private var isUnderline = false
    private var isStrike = false
    private var isBullet = false
    private var currentHeadingLevel: Int? = nil
    private var currentText = ""
    private var paragraphHTML = ""
    private var paragraphText = ""

    init(imageMap: [String: Data]) {
        self.imageMap = imageMap
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "w:tbl":
            inTable = true
            html += "<table border=\"1\" cellpadding=\"5\" cellspacing=\"0\">\n"
        case "w:tr":
            inRow = true
            html += "<tr>\n"
        case "w:tc":
            inCell = true
            html += "<td>"
        case "w:p":
            inParagraph = true
            paragraphHTML = ""
            paragraphText = ""
            currentHeadingLevel = nil
            isBullet = false
        case "w:pStyle":
            if let val = attributeDict["w:val"]?.lowercased() {
                if val.contains("heading1") || val == "title" {
                    currentHeadingLevel = 1
                } else if val.contains("heading2") || val == "subtitle" {
                    currentHeadingLevel = 2
                } else if val.contains("heading3") {
                    currentHeadingLevel = 3
                } else if val.contains("heading4") {
                    currentHeadingLevel = 4
                }
            }
        case "w:numPr":
            isBullet = true
        case "w:r":
            inRun = true
            isBold = false
            isItalic = false
            isUnderline = false
            isStrike = false
        case "w:b":
            if attributeDict["w:val"] != "0" && attributeDict["w:val"] != "false" { isBold = true }
        case "w:i":
            if attributeDict["w:val"] != "0" && attributeDict["w:val"] != "false" { isItalic = true }
        case "w:u":
            isUnderline = true
        case "w:strike":
            isStrike = true
        case "w:t":
            inText = true
            currentText = ""
        case "w:br":
            paragraphHTML += "<br/>"
        case "a:blip", "v:imagedata":
            if let rId = attributeDict["r:embed"] ?? attributeDict["r:id"],
               let imgData = imageMap[rId] {
                let processedData: Data
                if let uiImage = UIImage(data: imgData) {
                    let maxDimension: CGFloat = 1000
                    let w = uiImage.size.width
                    let h = uiImage.size.height
                    if max(w, h) > maxDimension {
                        let factor = maxDimension / max(w, h)
                        let newSize = CGSize(width: w * factor, height: h * factor)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1.0
                        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                        let resized = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
                        processedData = resized.jpegData(compressionQuality: 0.75) ?? imgData
                    } else {
                        processedData = uiImage.jpegData(compressionQuality: 0.8) ?? imgData
                    }
                } else {
                    processedData = imgData
                }
                let base64 = processedData.base64EncodedString()
                let mime = "image/jpeg"
                paragraphHTML += "<div style=\"text-align:center;margin:6pt 0;\"><img src=\"data:\(mime);base64,\(base64)\" style=\"max-width:100%;height:auto;\" /></div>"
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            inText = false
            paragraphText += currentText
            var escaped = currentText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if isBold { escaped = "<strong>\(escaped)</strong>" }
            if isItalic { escaped = "<em>\(escaped)</em>" }
            if isUnderline { escaped = "<u>\(escaped)</u>" }
            if isStrike { escaped = "<del>\(escaped)</del>" }
            paragraphHTML += escaped
        case "w:r":
            inRun = false
        case "w:p":
            inParagraph = false
            let pTrimmed = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pTrimmed.isEmpty {
                let prefix = isBullet ? "• " : ""
                plainText += (plainText.isEmpty ? "" : "\n\n") + prefix + pTrimmed
            }
            let trimmed = paragraphHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let level = currentHeadingLevel {
                    html += "<h\(level)>\(trimmed)</h\(level)>\n"
                } else if isBullet {
                    html += "<p style=\"margin-left: 16pt;\">• \(trimmed)</p>\n"
                } else {
                    html += "<p>\(trimmed)</p>\n"
                }
            }
        case "w:tc":
            inCell = false
            html += "</td>\n"
        case "w:tr":
            inRow = false
            html += "</tr>\n"
        case "w:tbl":
            inTable = false
            html += "</table>\n"
        default:
            break
        }
    }
}
