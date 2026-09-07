import Foundation
import CoreGraphics

// MARK: - Search Content Type

enum SearchContentType: String, Codable, CaseIterable {
    case handwriting = "handwriting"
    case text        = "text"
    case stickyNote  = "stickynote"
    case scan        = "scan"
    case pdf         = "pdf"
    case bookmark    = "bookmark"

    var localizedTitle: String {
        switch self {
        case .handwriting: return "Handschrift"
        case .text:        return "Text"
        case .stickyNote:  return "Haftnotiz"
        case .scan:        return "Dokumentenscan"
        case .pdf:         return "PDF-Inhalt"
        case .bookmark:    return "Lesezeichen"
        }
    }

    var iconName: String {
        switch self {
        case .handwriting: return "hand.draw.fill"
        case .text:        return "character.textbox"
        case .stickyNote:  return "note.text"
        case .scan:        return "doc.viewfinder.fill"
        case .pdf:         return "doc.text.fill"
        case .bookmark:    return "bookmark.fill"
        }
    }
}

// MARK: - Index Entry

struct IndexEntry {
    let contentType: SearchContentType
    let textContent: String
    let canvasRect: CGRect
    let pageIndex: Int
    let chunkId: String

    init(
        contentType: SearchContentType,
        textContent: String,
        canvasRect: CGRect,
        pageIndex: Int = 0,
        chunkId: String
    ) {
        self.contentType = contentType
        self.textContent = textContent
        self.canvasRect = canvasRect
        self.pageIndex = pageIndex
        self.chunkId = chunkId
    }
}

// MARK: - Search Result Item

struct SearchResultItem: Identifiable, Hashable {
    let id = UUID()
    let documentPath: String
    let documentName: String
    let contentType: SearchContentType
    let textContent: String
    let canvasRect: CGRect
    let pageIndex: Int
    let snippet: String

    init(
        documentPath: String,
        documentName: String,
        contentType: SearchContentType,
        textContent: String,
        canvasRect: CGRect,
        pageIndex: Int = 0,
        snippet: String = ""
    ) {
        self.documentPath = documentPath
        self.documentName = documentName
        self.contentType = contentType
        self.textContent = textContent
        self.canvasRect = canvasRect
        self.pageIndex = pageIndex
        self.snippet = snippet
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(documentPath)
        hasher.combine(contentType)
        hasher.combine(canvasRect.origin.x)
        hasher.combine(canvasRect.origin.y)
        hasher.combine(textContent)
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        return lhs.documentPath == rhs.documentPath &&
               lhs.contentType == rhs.contentType &&
               lhs.canvasRect == rhs.canvasRect &&
               lhs.textContent == rhs.textContent
    }
}
