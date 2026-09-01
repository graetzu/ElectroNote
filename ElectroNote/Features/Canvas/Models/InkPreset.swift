import UIKit
import PencilKit

// MARK: - Ink Preset

struct InkPreset: Identifiable, Codable {
    var id   = UUID()
    var name: String
    var inkTypeName: String   // "pen" | "pencil" | "marker" | "monoline" | "fountainPen" | "watercolor" | "crayon"
    var red, green, blue, alpha: Double
    var width: Double

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    var pkTool: PKInkingTool {
        PKInkingTool(inkType, color: uiColor, width: width)
    }

    var inkType: PKInkingTool.InkType {
        switch inkTypeName {
        case "pencil":      return .pencil
        case "marker":      return .marker
        case "monoline":    return .monoline
        case "fountainPen": return .fountainPen
        case "watercolor":  return .watercolor
        case "crayon":      return .crayon
        default:            return .pen
        }
    }

    init(name: String, inkType: PKInkingTool.InkType, color: UIColor, width: Double) {
        self.name = name
        self.inkTypeName = inkType.rawStringValue
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r); self.green = Double(g)
        self.blue = Double(b); self.alpha = Double(a)
        self.width = width
    }
}

extension PKInkingTool.InkType {
    var rawStringValue: String {
        switch self {
        case .pen:        return "pen"
        case .pencil:     return "pencil"
        case .marker:     return "marker"
        case .monoline:   return "monoline"
        case .fountainPen:return "fountainPen"
        case .watercolor: return "watercolor"
        case .crayon:     return "crayon"
        @unknown default: return "pen"
        }
    }
}

// MARK: - Preset Store

final class InkPresetStore: ObservableObject {
    static let shared = InkPresetStore()

    @Published private(set) var presets: [InkPreset] {
        didSet { save() }
    }

    private let key = "ElectroNoteInkPresets"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([InkPreset].self, from: data) {
            presets = stored
        } else {
            presets = InkPresetStore.defaults
        }
    }

    static var defaults: [InkPreset] = [
        InkPreset(name: "Schwarz Stift",   inkType: .pen,    color: .black,       width: 2),
        InkPreset(name: "Rot Stift",       inkType: .pen,    color: .systemRed,   width: 2),
        InkPreset(name: "Blau Marker",     inkType: .marker, color: .systemBlue,  width: 8),
        InkPreset(name: "Grün Marker",     inkType: .marker, color: .systemGreen, width: 8),
        InkPreset(name: "Bleistift",       inkType: .pencil, color: .darkGray,    width: 3),
    ]

    func add(_ preset: InkPreset) { presets.append(preset) }

    func delete(id: UUID) { presets.removeAll { $0.id == id } }

    func replace(_ preset: InkPreset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) { presets[i] = preset }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
