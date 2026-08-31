import Foundation

// MARK: - BackgroundStyle

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case blank   = "Leer"
    case lined   = "Liniert"
    case grid    = "Kariert"
    case dotted  = "Gepunktet"

    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .blank:  return "rectangle"
        case .lined:  return "line.3.horizontal"
        case .grid:   return "squareshape.split.2x2"
        case .dotted: return "ellipsis"
        }
    }
}

// MARK: - Document model

struct NotebookDocument: Codable {
    var background: BackgroundStyle = .grid
    var documentHeight: CGFloat = NotebookDocument.initialHeight
    var insertedPDFs:   [InsertedPDF]   = []
    var insertedImages: [InsertedImage] = []
    var mathEnabled:    Bool = false

    static let pageWidth:     CGFloat = 595
    static let pageHeight:    CGFloat = 842
    static let initialHeight: CGFloat = pageHeight * 20
}

// MARK: - Inserted content

struct InsertedPDF: Identifiable, Codable {
    let id: UUID
    let filename: String
    let startY: CGFloat
    let pageHeights: [CGFloat]

    var endY: CGFloat { startY + pageHeights.reduce(0, +) }
}

struct InsertedImage: Identifiable, Codable {
    let id: UUID
    let filename: String
    let startY: CGFloat
    let width: CGFloat
    let height: CGFloat
}
