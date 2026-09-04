import Foundation

// MARK: - BackgroundStyle

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case blank   = "Leer"
    case lined   = "Liniert"
    case grid    = "Kariert"
    case dotted  = "Gepunktet"
    case cornell = "Cornell"

    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .blank:   return "rectangle"
        case .lined:   return "line.3.horizontal"
        case .grid:    return "squareshape.split.2x2"
        case .dotted:  return "ellipsis"
        case .cornell: return "rectangle.split.3x1"
        }
    }
}

// MARK: - LineSpacing

enum LineSpacing: String, Codable, CaseIterable, Identifiable {
    case narrow = "Eng"
    case medium = "Mittel"
    case wide   = "Weit"

    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .narrow: return 20
        case .medium: return 28
        case .wide:   return 38
        }
    }
}

// MARK: - Bookmark

struct Bookmark: Identifiable, Codable {
    let id: UUID
    var title: String
    let y: CGFloat
}

// MARK: - StickyNote

struct StickyNote: Identifiable, Codable {
    let id: UUID
    var text: String
    var x: CGFloat   // canvas content coordinates
    var y: CGFloat
    var colorIndex: Int
    var drawingData: Data?

    init(id: UUID = UUID(), text: String = "", x: CGFloat, y: CGFloat, colorIndex: Int = 0, drawingData: Data? = nil) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.colorIndex = colorIndex
        self.drawingData = drawingData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self, forKey: .id)
        text        = try c.decode(String.self, forKey: .text)
        x           = try c.decode(CGFloat.self, forKey: .x)
        y           = try c.decode(CGFloat.self, forKey: .y)
        colorIndex  = try c.decode(Int.self, forKey: .colorIndex)
        drawingData = try c.decodeIfPresent(Data.self, forKey: .drawingData)
    }
}

// MARK: - Document model

struct NotebookDocument: Codable {
    var background:      BackgroundStyle = .grid
    var lineSpacing:     LineSpacing     = .medium
    var documentHeight:  CGFloat         = NotebookDocument.initialHeight
    var insertedPDFs:    [InsertedPDF]   = []
    var insertedImages:  [InsertedImage] = []
    var mathEnabled:      Bool            = false
    var darkDrawingMode:  Bool            = false
    var shapeSnapEnabled: Bool            = false
    var bookmarks:       [Bookmark]      = []
    var stickyNotes:     [StickyNote]    = []

    static let pageWidth:     CGFloat = 595
    static let pageHeight:    CGFloat = 842
    static let initialHeight: CGFloat = pageHeight * 20
}

// MARK: - Inserted content

struct InsertedPDF: Identifiable, Codable {
    let id: UUID
    let filename: String
    var startY: CGFloat
    var pageHeights: [CGFloat]

    var endY: CGFloat { startY + pageHeights.reduce(0, +) }
}

struct InsertedImage: Identifiable, Codable {
    let id: UUID
    var filename: String
    var startX: CGFloat
    var startY: CGFloat
    var width: CGFloat
    var height: CGFloat
    var textContent: String?
    var fontSize: CGFloat?
    var fontDesign: String?
    var fontColorHex: String?
    var rotation: CGFloat?

    init(id: UUID = UUID(), filename: String, startX: CGFloat = 0,
         startY: CGFloat, width: CGFloat, height: CGFloat,
         textContent: String? = nil, fontSize: CGFloat? = nil,
         fontDesign: String? = nil, fontColorHex: String? = nil,
         rotation: CGFloat? = 0) {
        self.id = id; self.filename = filename; self.startX = startX
        self.startY = startY; self.width = width; self.height = height
        self.textContent = textContent; self.fontSize = fontSize
        self.fontDesign = fontDesign; self.fontColorHex = fontColorHex
        self.rotation = rotation
    }

    // Backward-compatible decoder: startX defaults to 0 for old documents, rotation defaults to 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self, forKey: .id)
        filename     = try c.decode(String.self, forKey: .filename)
        startX       = try c.decodeIfPresent(CGFloat.self, forKey: .startX) ?? 0
        startY       = try c.decode(CGFloat.self, forKey: .startY)
        width        = try c.decode(CGFloat.self, forKey: .width)
        height       = try c.decode(CGFloat.self, forKey: .height)
        textContent  = try c.decodeIfPresent(String.self, forKey: .textContent)
        fontSize     = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        fontDesign   = try c.decodeIfPresent(String.self, forKey: .fontDesign)
        fontColorHex = try c.decodeIfPresent(String.self, forKey: .fontColorHex)
        rotation     = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }
}

