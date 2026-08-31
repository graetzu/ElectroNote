import SwiftUI

struct ClipArtItem: Identifiable, Codable, Equatable {
    let id: UUID
    var symbolName: String
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var colorKey: ClipArtColor

    init(symbolName: String, at point: CGPoint, size: CGFloat = 56) {
        id = UUID()
        self.symbolName = symbolName
        x = point.x
        y = point.y
        self.size = size
        colorKey = .primary
    }
}

enum ClipArtColor: String, Codable, CaseIterable {
    case primary, blue, red, green, orange, purple

    var color: Color {
        switch self {
        case .primary: return .primary
        case .blue:    return .blue
        case .red:     return .red
        case .green:   return .green
        case .orange:  return .orange
        case .purple:  return .purple
        }
    }

    var label: String { rawValue.capitalized }
}
