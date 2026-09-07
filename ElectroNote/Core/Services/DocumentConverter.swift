import UIKit
import PDFKit
import UniformTypeIdentifiers
import zlib

@MainActor
final class DocumentConverter: NSObject {

    static let shared = DocumentConverter()

    /// Supported document import UTTypes
    static let supportedTypes: [UTType] = [
        .pdf,
        .plainText,
        .rtf,
        .text,
        .html,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("com.microsoft.word.doc") ?? .data
    ]

    /// Converts any supported document (.docx, .rtf, .txt, .html, .pdf) into a temporary PDF URL.
    func convertToPDF(sourceURL: URL) async throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "pdf" {
            return sourceURL
        }

        if ext == "docx" {
            return try convertDocxToPDF(sourceURL: sourceURL)
        }

        if ext == "rtf" || ext == "txt" || ext == "text" {
            return try convertTextOrRTFToPDF(sourceURL: sourceURL)
        }

        if ext == "html" || ext == "htm" {
            return try convertHTMLToPDF(sourceURL: sourceURL)
        }

        if ext == "doc" {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Ältere .doc-Dateien (Word 97-2004) werden nicht unterstützt. Bitte speichere das Dokument im modernen Word-Format (.docx) oder als PDF."]
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

    private func convertDocxToPDF(sourceURL: URL) throws -> URL {
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

    // MARK: - HTML Conversion

    private func convertHTMLToPDF(sourceURL: URL) throws -> URL {
        let htmlString = try String(contentsOf: sourceURL, encoding: .utf8)
        return try renderHTMLToPDF(htmlString)
    }

    private func renderHTMLToPDF(_ htmlString: String) throws -> URL {
        guard let htmlData = htmlString.data(using: .utf8) else {
            throw NSError(
                domain: "DocumentConverter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HTML-Inhalt konnte nicht geladen werden."]
            )
        }

        let attrString = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )

        return try Self.renderAttributedStringToPDF(attrString)
    }

    // MARK: - Plain Text & RTF Conversion

    private func convertTextOrRTFToPDF(sourceURL: URL) throws -> URL {
        let isRTF = sourceURL.pathExtension.lowercased() == "rtf"
        let docType: NSAttributedString.DocumentType = isRTF ? .rtf : .plain
        let attrString = try NSAttributedString(
            url: sourceURL,
            options: [.documentType: docType],
            documentAttributes: nil
        )

        return try Self.renderAttributedStringToPDF(attrString)
    }

    // MARK: - Shared PDF Renderer

    private static func renderAttributedStringToPDF(_ attrString: NSAttributedString) throws -> URL {
        let printFormatter = UISimpleTextPrintFormatter(attributedText: attrString)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)

        let pageWidth: CGFloat = 595.2   // Standard A4
        let pageHeight: CGFloat = 841.8  // Standard A4
        let margin: CGFloat = 36.0
        let printable = CGRect(x: margin, y: margin, width: pageWidth - margin * 2, height: pageHeight - margin * 2)
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
                let base64 = imgData.base64EncodedString()
                let mime = imgData.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : "image/png"
                paragraphHTML += "<div style=\"text-align:center;margin:6pt 0;\"><img src=\"data:\(mime);base64,\(base64)\" /></div>"
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
