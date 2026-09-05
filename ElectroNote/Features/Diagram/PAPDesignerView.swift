import SwiftUI
import PencilKit

// MARK: - Shape types (DIN 66001 Standard)

enum PAPShapeType: String, CaseIterable, Identifiable {
    case start          = "Start"
    case end            = "Ende"
    case process        = "Prozess"
    case io             = "Ein-/Ausgabe"
    case decision       = "Verzweigung"
    case subroutine     = "Unterprogramm"
    case connector      = "Konnektor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:        return "Start"
        case .end:          return "Ende"
        case .process:      return "Prozess"
        case .io:           return "Ein-/Ausgabe"
        case .decision:     return "Verzweigung"
        case .subroutine:   return "Unterprogramm"
        case .connector:    return "Verbindung"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .start, .end:    return 150
        case .process:        return 160
        case .io:             return 160
        case .decision:       return 150
        case .subroutine:     return 160
        case .connector:      return 32
        }
    }

    var defaultHeight: CGFloat {
        switch self {
        case .start, .end:    return 52
        case .process:        return 54
        case .io:             return 54
        case .decision:       return 70
        case .subroutine:     return 54
        case .connector:      return 32
        }
    }

    var fillColor: Color {
        switch self {
        case .start, .end:    return Color(red: 0.76, green: 0.88, blue: 0.98)
        case .process:        return Color(red: 0.74, green: 0.94, blue: 0.78)
        case .io:             return Color(red: 0.98, green: 0.84, blue: 0.74)
        case .decision:       return Color(red: 1.00, green: 0.88, blue: 0.45)
        case .subroutine:     return Color(red: 0.88, green: 0.80, blue: 0.98)
        case .connector:      return Color(red: 0.90, green: 0.92, blue: 0.95)
        }
    }

    var strokeColor: Color {
        switch self {
        case .start, .end:    return Color(red: 0.18, green: 0.45, blue: 0.75)
        case .process:        return Color(red: 0.18, green: 0.58, blue: 0.28)
        case .io:             return Color(red: 0.82, green: 0.42, blue: 0.18)
        case .decision:       return Color(red: 0.85, green: 0.58, blue: 0.08)
        case .subroutine:     return Color(red: 0.52, green: 0.28, blue: 0.75)
        case .connector:      return Color(white: 0.35)
        }
    }

    var icon: String {
        switch self {
        case .start, .end:    return "oval"
        case .process:        return "rectangle"
        case .io:             return "parallelogram"
        case .decision:       return "diamond"
        case .subroutine:     return "rectangle.split.3x1"
        case .connector:      return "circle.fill"
        }
    }
}

// MARK: - Grid & Fixed Column System (Feste Spaltenbreite & Zeilen)

struct PAPGrid {
    static let colWidth: CGFloat = 210
    static let rowHeight: CGFloat = 115
    static let originX: CGFloat = 340   // Column 1 is centered here (Column 0 = Left Branch, Column 1 = Main, Column 2 = Right Branch)
    static let originY: CGFloat = 85

    static func center(col: Int, row: Int) -> CGPoint {
        let x = originX + CGFloat(col - 1) * colWidth
        let y = originY + CGFloat(row) * rowHeight
        return CGPoint(x: x, y: y)
    }

    static func nearestGrid(from point: CGPoint) -> (col: Int, row: Int) {
        let col = max(0, min(5, Int(round((point.x - originX) / colWidth)) + 1))
        let row = max(0, min(25, Int(round((point.y - originY) / rowHeight))))
        return (col, row)
    }
}

// MARK: - Models

struct PAPNode: Identifiable, Equatable {
    var id: UUID = UUID()
    var type: PAPShapeType
    var label: String
    var col: Int        // 0 = Linker Zweig, 1 = Hauptprogramm, 2 = Rechter Zweig 1, 3 = Rechter Zweig 2
    var row: Int        // 0, 1, 2, 3...
    var tag: String = "" // e.g. "E" (Eingabe) oder "A" (Ausgabe)

    var cx: CGFloat { PAPGrid.center(col: col, row: row).x }
    var cy: CGFloat { PAPGrid.center(col: col, row: row).y }
}

enum PAPBranchPort: String, CaseIterable, Codable, Identifiable {
    case bottom
    case right
    case left
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: return "Unten (↓)"
        case .right:  return "Rechts (→)"
        case .left:   return "Links (←)"
        case .top:    return "Oben (↑)"
        }
    }
}

struct PAPEdge: Identifiable, Equatable {
    var id: UUID = UUID()
    var fromId: UUID
    var toId: UUID
    var label: String = "" // "ja", "nein", "wahr", "falsch", etc.
    var fromPort: PAPBranchPort = .bottom
}

// MARK: - Orthogonal 4-Direction Routing Engine (Nur 4 Richtungen, 90° Manhattan Paths)

enum ArrowDirection {
    case down, up, right, left
}

struct OrthogonalRoutingEngine {
    static func route(from: PAPNode, to: PAPNode, fromPort: PAPBranchPort) -> (points: [CGPoint], arrowDir: ArrowDirection, labelPos: CGPoint) {
        let p1 = CGPoint(x: from.cx, y: from.cy)
        let p2 = CGPoint(x: to.cx, y: to.cy)
        let w1 = from.type.defaultWidth / 2
        let h1 = from.type.defaultHeight / 2
        let w2 = to.type.defaultWidth / 2
        let h2 = to.type.defaultHeight / 2

        let c1 = from.col, r1 = from.row
        let c2 = to.col,   r2 = to.row

        // ==========================================
        // 1. SAME COLUMN (c1 == c2)
        // ==========================================
        if c1 == c2 {
            // A) Direct neighbor below (r2 == r1 + 1) exiting bottom
            if r2 == r1 + 1 && fromPort == .bottom {
                let start = CGPoint(x: p1.x, y: p1.y + h1)
                let end   = CGPoint(x: p2.x, y: p2.y - h2)
                let label = CGPoint(x: p1.x + 16, y: (start.y + end.y) / 2)
                return ([start, end], .down, label)
            }

            // B) Skipping steps downwards in the same column (r2 > r1) or side exit
            if r2 > r1 {
                if fromPort == .left {
                    let bypassX = p1.x - w1 - 28
                    let start = CGPoint(x: p1.x - w1, y: p1.y)
                    let corner1 = CGPoint(x: bypassX, y: p1.y)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x - w2, y: p2.y)
                    let label = CGPoint(x: bypassX - 16, y: (p1.y + p2.y) / 2)
                    return ([start, corner1, corner2, end], .right, label)
                } else if fromPort == .right {
                    let bypassX = p1.x + w1 + 28
                    let start = CGPoint(x: p1.x + w1, y: p1.y)
                    let corner1 = CGPoint(x: bypassX, y: p1.y)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x + w2, y: p2.y)
                    let label = CGPoint(x: bypassX + 16, y: (p1.y + p2.y) / 2)
                    return ([start, corner1, corner2, end], .left, label)
                } else {
                    // fromPort == .bottom, but r2 > r1 + 1 (Bypass around intermediate blocks)
                    let bypassX = p1.x + w1 + 28
                    let start = CGPoint(x: p1.x, y: p1.y + h1)
                    let stepY = p1.y + h1 + 14
                    let corner0 = CGPoint(x: p1.x, y: stepY)
                    let corner1 = CGPoint(x: bypassX, y: stepY)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x + w2, y: p2.y)
                    let label = CGPoint(x: bypassX + 16, y: (stepY + p2.y) / 2)
                    return ([start, corner0, corner1, corner2, end], .left, label)
                }
            }

            // C) Loopback upwards in same column (r2 <= r1)
            if r2 <= r1 {
                if fromPort == .right {
                    let bypassX = p1.x + w1 + 28
                    let start = CGPoint(x: p1.x + w1, y: p1.y)
                    let corner1 = CGPoint(x: bypassX, y: p1.y)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x + w2, y: p2.y)
                    let label = CGPoint(x: bypassX + 16, y: (p1.y + p2.y) / 2)
                    return ([start, corner1, corner2, end], .left, label)
                } else if fromPort == .top {
                    let bypassX = p1.x - w1 - 28
                    let start = CGPoint(x: p1.x, y: p1.y - h1)
                    let stepY = max(0, p1.y - h1 - 14)
                    let corner0 = CGPoint(x: p1.x, y: stepY)
                    let corner1 = CGPoint(x: bypassX, y: stepY)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x - w2, y: p2.y)
                    let label = CGPoint(x: bypassX - 16, y: (p1.y + p2.y) / 2)
                    return ([start, corner0, corner1, corner2, end], .right, label)
                } else {
                    // Default loopback (left bypass)
                    let bypassX = p1.x - w1 - 28
                    let start = (fromPort == .bottom) ? CGPoint(x: p1.x, y: p1.y + h1) : CGPoint(x: p1.x - w1, y: p1.y)
                    if fromPort == .bottom {
                        let stepY = p1.y + h1 + 14
                        let corner0 = CGPoint(x: p1.x, y: stepY)
                        let corner1 = CGPoint(x: bypassX, y: stepY)
                        let corner2 = CGPoint(x: bypassX, y: p2.y)
                        let end = CGPoint(x: p2.x - w2, y: p2.y)
                        let label = CGPoint(x: bypassX - 16, y: (p1.y + p2.y) / 2)
                        return ([start, corner0, corner1, corner2, end], .right, label)
                    } else {
                        let corner1 = CGPoint(x: bypassX, y: p1.y)
                        let corner2 = CGPoint(x: bypassX, y: p2.y)
                        let end = CGPoint(x: p2.x - w2, y: p2.y)
                        let label = CGPoint(x: bypassX - 16, y: (p1.y + p2.y) / 2)
                        return ([start, corner1, corner2, end], .right, label)
                    }
                }
            }
        }

        // ==========================================
        // 2. DIFFERENT COLUMNS (c1 != c2)
        // ==========================================

        // A) Same Row (r1 == r2)
        if r1 == r2 {
            if c2 > c1 {
                let start = CGPoint(x: p1.x + w1, y: p1.y)
                let end = CGPoint(x: p2.x - w2, y: p2.y)
                let label = CGPoint(x: (start.x + end.x) / 2, y: p1.y - 12)
                return ([start, end], .right, label)
            } else {
                let start = CGPoint(x: p1.x - w1, y: p1.y)
                let end = CGPoint(x: p2.x + w2, y: p2.y)
                let label = CGPoint(x: (start.x + end.x) / 2, y: p1.y - 12)
                return ([start, end], .left, label)
            }
        }

        // B) Target is Downwards in another column (r2 > r1)
        if r2 > r1 {
            if fromPort == .right || (c2 > c1 && fromPort != .left && fromPort != .bottom) {
                if c2 > c1 {
                    let start = CGPoint(x: p1.x + w1, y: p1.y)
                    let corner1 = CGPoint(x: p2.x, y: p1.y)
                    let end = CGPoint(x: p2.x, y: p2.y - h2)
                    let label = CGPoint(x: (start.x + corner1.x) / 2, y: p1.y - 12)
                    return ([start, corner1, end], .down, label)
                } else {
                    let bypassX = p1.x + w1 + 20
                    let start = CGPoint(x: p1.x + w1, y: p1.y)
                    let corner1 = CGPoint(x: bypassX, y: p1.y)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x + w2, y: p2.y)
                    let label = CGPoint(x: bypassX + 14, y: (p1.y + p2.y) / 2)
                    return ([start, corner1, corner2, end], .left, label)
                }
            } else if fromPort == .left || (c2 < c1 && fromPort != .right && fromPort != .bottom) {
                if c2 < c1 {
                    let start = CGPoint(x: p1.x - w1, y: p1.y)
                    let corner1 = CGPoint(x: p2.x, y: p1.y)
                    let end = CGPoint(x: p2.x, y: p2.y - h2)
                    let label = CGPoint(x: (start.x + corner1.x) / 2, y: p1.y - 12)
                    return ([start, corner1, end], .down, label)
                } else {
                    let bypassX = p1.x - w1 - 20
                    let start = CGPoint(x: p1.x - w1, y: p1.y)
                    let corner1 = CGPoint(x: bypassX, y: p1.y)
                    let corner2 = CGPoint(x: bypassX, y: p2.y)
                    let end = CGPoint(x: p2.x - w2, y: p2.y)
                    let label = CGPoint(x: bypassX - 14, y: (p1.y + p2.y) / 2)
                    return ([start, corner1, corner2, end], .right, label)
                }
            } else {
                // fromPort == .bottom
                let start = CGPoint(x: p1.x, y: p1.y + h1)
                let corner1 = CGPoint(x: p1.x, y: p2.y)
                let end = CGPoint(x: c1 > c2 ? (p2.x + w2) : (p2.x - w2), y: p2.y)
                let dir: ArrowDirection = (c1 > c2) ? .left : .right
                let label = CGPoint(x: (start.x + end.x) / 2, y: p2.y - 12)
                return ([start, corner1, end], dir, label)
            }
        }

        // C) Target is Upwards in another column (r2 < r1)
        if r2 < r1 {
            if fromPort == .right || c2 > c1 {
                let rightColX = max(p1.x + PAPGrid.colWidth, p2.x + w2 + 20)
                let start = CGPoint(x: p1.x + w1, y: p1.y)
                let corner1 = CGPoint(x: rightColX, y: p1.y)
                let corner2 = CGPoint(x: rightColX, y: p2.y)
                let end = CGPoint(x: p2.x + w2, y: p2.y)
                let label = CGPoint(x: (start.x + corner1.x) / 2, y: p1.y - 12)
                return ([start, corner1, corner2, end], .left, label)
            } else if fromPort == .left || c2 < c1 {
                let leftColX = min(p1.x - PAPGrid.colWidth, p2.x - w2 - 20)
                let start = CGPoint(x: p1.x - w1, y: p1.y)
                let corner1 = CGPoint(x: leftColX, y: p1.y)
                let corner2 = CGPoint(x: leftColX, y: p2.y)
                let end = CGPoint(x: p2.x - w2, y: p2.y)
                let label = CGPoint(x: (start.x + corner1.x) / 2, y: p1.y - 12)
                return ([start, corner1, corner2, end], .right, label)
            } else {
                let start = CGPoint(x: p1.x, y: p1.y - h1)
                let corner1 = CGPoint(x: p1.x, y: p2.y)
                let end = CGPoint(x: c2 > c1 ? (p2.x - w2) : (p2.x + w2), y: p2.y)
                let dir: ArrowDirection = (c2 > c1) ? .right : .left
                let label = CGPoint(x: p1.x + (c2 > c1 ? 16 : -16), y: (start.y + p2.y) / 2)
                return ([start, corner1, end], dir, label)
            }
        }

        // Fallback
        let start = CGPoint(x: p1.x, y: p1.y + h1)
        let end   = CGPoint(x: p2.x, y: p2.y - h2)
        return ([start, end], .down, CGPoint(x: p1.x + 14, y: (p1.y + p2.y) / 2))
    }
}

// MARK: - Shapes

struct DiamondShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

struct ParallelogramShape: Shape {
    var slant: CGFloat = 14
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: r.minX + slant, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX,         y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX,         y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct SubroutineShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Outer rect
        p.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
        // Inner double vertical lines
        let stripeWidth: CGFloat = 12
        p.move(to: CGPoint(x: r.minX + stripeWidth, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + stripeWidth, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - stripeWidth, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - stripeWidth, y: r.maxY))
        return p
    }
}

struct OrthogonalEdgeShape: Shape {
    let points: [CGPoint]
    let arrowDir: ArrowDirection
    let arrowSize: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        guard points.count >= 2 else { return Path() }
        var p = Path()
        p.move(to: points[0])
        for pt in points.dropFirst() {
            p.addLine(to: pt)
        }

        if let end = points.last {
            var arrow = Path()
            switch arrowDir {
            case .down:
                arrow.move(to: CGPoint(x: end.x - arrowSize * 0.75, y: end.y - arrowSize * 1.3))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x + arrowSize * 0.75, y: end.y - arrowSize * 1.3))
            case .up:
                arrow.move(to: CGPoint(x: end.x - arrowSize * 0.75, y: end.y + arrowSize * 1.3))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x + arrowSize * 0.75, y: end.y + arrowSize * 1.3))
            case .right:
                arrow.move(to: CGPoint(x: end.x - arrowSize * 1.3, y: end.y - arrowSize * 0.75))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x - arrowSize * 1.3, y: end.y + arrowSize * 0.75))
            case .left:
                arrow.move(to: CGPoint(x: end.x + arrowSize * 1.3, y: end.y - arrowSize * 0.75))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x + arrowSize * 1.3, y: end.y + arrowSize * 0.75))
            }
            p.addPath(arrow)
        }
        return p
    }
}

// MARK: - Templates

enum PAPTemplate: String, CaseIterable, Identifiable {
    case linear       = "Linearer Ablauf"
    case ifElse       = "Verzweigung (If/Else)"
    case whileLoop    = "Kopfgesteuerte Schleife (While)"
    case doWhileLoop  = "Fußgesteuerte Schleife (Do-While)"
    case empty        = "Neuer Start"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .linear:      return "arrow.down"
        case .ifElse:      return "arrow.triangle.branch"
        case .whileLoop:   return "arrow.triangle.2.circlepath"
        case .doWhileLoop: return "repeat"
        case .empty:       return "plus.square"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class PAPDesignerViewModel: ObservableObject {
    @Published var nodes: [PAPNode] = []
    @Published var edges: [PAPEdge] = []
    @Published var selectedId: UUID? = nil
    @Published var connectMode: Bool = false
    @Published var connectFromId: UUID? = nil
    @Published var showGridGuides: Bool = true

    private var undoStack: [([PAPNode], [PAPEdge])] = []
    private var redoStack: [([PAPNode], [PAPEdge])] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedNode: PAPNode? {
        guard let id = selectedId else { return nil }
        return nodes.first { $0.id == id }
    }

    init() {
        loadTemplate(.linear)
    }

    func pushUndo() {
        undoStack.append((nodes, edges))
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append((nodes, edges))
        nodes = prev.0
        edges = prev.1
        selectedId = nil
        connectFromId = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((nodes, edges))
        nodes = next.0
        edges = next.1
        selectedId = nil
        connectFromId = nil
    }

    // MARK: Step-by-Step Construction (Bedienung wie PAP Designer)

    /// Inserts a block directly below in the same column at (col, row + 1) with automatic downward arrow
    func insertBelow(fromNode: PAPNode, type: PAPShapeType, label: String? = nil, tag: String = "") {
        pushUndo()
        let targetCol = fromNode.col
        let targetRow = fromNode.row + 1

        // Shift down all existing nodes in the same column to make clean space
        for i in 0..<nodes.count {
            if nodes[i].col == targetCol && nodes[i].row >= targetRow {
                nodes[i].row += 1
            }
        }

        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = "Anweisung"
        case .io:           defaultLabel = tag.isEmpty ? "Eingabe" : (tag == "A" ? "Ausgabe" : "Eingabe")
        case .decision:     defaultLabel = "Bedingung?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: targetCol,
            row: targetRow,
            tag: tag.isEmpty && type == .io ? "E" : tag
        )
        nodes.append(newNode)

        // Connect from original node
        let edgeLabel = fromNode.type == .decision ? "ja" : ""
        edges.append(PAPEdge(fromId: fromNode.id, toId: newNode.id, label: edgeLabel, fromPort: .bottom))

        selectedId = newNode.id
    }

    /// Branches to the right into the adjacent column. If goUp == true, routes upwards into (col + 1, row - 1).
    func branchRight(fromDecision: PAPNode, type: PAPShapeType = .process, label: String? = nil, edgeLabel: String = "nein", goUp: Bool = false) {
        pushUndo()
        let targetCol = min(5, fromDecision.col + 1)
        let targetRow = goUp ? max(0, fromDecision.row - 1) : (fromDecision.row + 1)

        // Shift down if occupied
        for i in 0..<nodes.count {
            if nodes[i].col == targetCol && nodes[i].row >= targetRow {
                nodes[i].row += 1
            }
        }

        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = goUp ? "Schleife" : "Anweisung"
        case .io:           defaultLabel = "Ausgabe"
        case .decision:     defaultLabel = "Bedingung 2?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: targetCol,
            row: targetRow,
            tag: type == .io ? "A" : ""
        )
        nodes.append(newNode)

        edges.append(PAPEdge(fromId: fromDecision.id, toId: newNode.id, label: edgeLabel, fromPort: .right))
        selectedId = newNode.id
    }

    /// Branches to the left into the adjacent column. If goUp == true, routes upwards into (col - 1, row - 1).
    func branchLeft(fromDecision: PAPNode, type: PAPShapeType = .process, label: String? = nil, edgeLabel: String = "nein", goUp: Bool = false) {
        pushUndo()
        let targetCol = max(0, fromDecision.col - 1)
        let targetRow = goUp ? max(0, fromDecision.row - 1) : (fromDecision.row + 1)

        for i in 0..<nodes.count {
            if nodes[i].col == targetCol && nodes[i].row >= targetRow {
                nodes[i].row += 1
            }
        }

        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = goUp ? "Schleife" : "Anweisung"
        case .io:           defaultLabel = "Ausgabe"
        case .decision:     defaultLabel = "Bedingung 2?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: targetCol,
            row: targetRow,
            tag: type == .io ? "A" : ""
        )
        nodes.append(newNode)

        edges.append(PAPEdge(fromId: fromDecision.id, toId: newNode.id, label: edgeLabel, fromPort: .left))
        selectedId = newNode.id
    }

    /// Branches upwards from a decision to a new block above (for loops / retry logic)
    func branchUp(fromDecision: PAPNode, type: PAPShapeType = .process, label: String? = nil, edgeLabel: String = "nein", port: PAPBranchPort = .top) {
        pushUndo()
        let targetCol: Int
        switch port {
        case .left:  targetCol = max(0, fromDecision.col - 1)
        case .right: targetCol = min(5, fromDecision.col + 1)
        default:     targetCol = fromDecision.col
        }
        let targetRow = max(0, fromDecision.row - 1)

        for i in 0..<nodes.count {
            if nodes[i].col == targetCol && nodes[i].row >= targetRow {
                nodes[i].row += 1
            }
        }

        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = "Wiederholung"
        case .io:           defaultLabel = "Eingabe"
        case .decision:     defaultLabel = "Bedingung 2?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: targetCol,
            row: targetRow,
            tag: type == .io ? "E" : ""
        )
        nodes.append(newNode)

        edges.append(PAPEdge(fromId: fromDecision.id, toId: newNode.id, label: edgeLabel, fromPort: port))
        selectedId = newNode.id
    }

    /// Inserts a block directly above in the same column at (col, row) and shifts original block down
    func insertAbove(fromNode: PAPNode, type: PAPShapeType, label: String? = nil, tag: String = "", edgeLabel: String = "") {
        pushUndo()
        let targetCol = fromNode.col
        let targetRow = fromNode.row

        // Shift down the original node and all nodes below it
        for i in 0..<nodes.count {
            if nodes[i].col == targetCol && nodes[i].row >= targetRow {
                nodes[i].row += 1
            }
        }

        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = "Anweisung"
        case .io:           defaultLabel = tag.isEmpty ? "Eingabe" : (tag == "A" ? "Ausgabe" : "Eingabe")
        case .decision:     defaultLabel = "Bedingung?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: targetCol,
            row: targetRow,
            tag: tag.isEmpty && type == .io ? "E" : tag
        )
        nodes.append(newNode)

        edges.append(PAPEdge(fromId: newNode.id, toId: fromNode.id, label: edgeLabel, fromPort: .bottom))
        selectedId = newNode.id
    }

    /// Adds a standalone node snapped to a grid column & row
    func addNode(type: PAPShapeType, col: Int = 1, row: Int? = nil, label: String? = nil) {
        pushUndo()
        let targetRow = row ?? ((nodes.filter { $0.col == col }.map { $0.row }.max() ?? -1) + 1)
        let defaultLabel: String
        switch type {
        case .start:        defaultLabel = "Start"
        case .end:          defaultLabel = "Ende"
        case .process:      defaultLabel = "Anweisung"
        case .io:           defaultLabel = "Ein-/Ausgabe"
        case .decision:     defaultLabel = "Bedingung?"
        case .subroutine:   defaultLabel = "Unterprogramm()"
        case .connector:    defaultLabel = ""
        }

        let newNode = PAPNode(
            type: type,
            label: label ?? defaultLabel,
            col: col,
            row: targetRow,
            tag: type == .io ? "E" : ""
        )
        nodes.append(newNode)
        selectedId = newNode.id
    }

    func moveNode(id: UUID, toCol: Int, toRow: Int) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        if nodes[index].col != toCol || nodes[index].row != toRow {
            pushUndo()
            nodes[index].col = toCol
            nodes[index].row = toRow
        }
    }

    func tapNode(id: UUID) {
        if connectMode {
            if let from = connectFromId, from != id {
                connect(fromId: from, toId: id)
                connectFromId = nil
                connectMode = false
            } else {
                connectFromId = id
            }
        } else {
            selectedId = (selectedId == id) ? nil : id
        }
    }

    func connect(fromId: UUID, toId: UUID, label: String = "", port: PAPBranchPort? = nil) {
        guard fromId != toId else { return }
        guard !edges.contains(where: { $0.fromId == fromId && $0.toId == toId }) else { return }
        guard let fromNode = nodes.first(where: { $0.id == fromId }),
              let toNode   = nodes.first(where: { $0.id == toId }) else { return }

        pushUndo()
        let resolvedPort: PAPBranchPort
        if let explicitPort = port {
            resolvedPort = explicitPort
        } else if fromNode.type == .decision {
            if toNode.row < fromNode.row {
                // Connecting to a node above (Loopback / Schleife)
                if toNode.col > fromNode.col { resolvedPort = .right }
                else if toNode.col < fromNode.col { resolvedPort = .left }
                else { resolvedPort = .right }
            } else if toNode.row == fromNode.row {
                resolvedPort = (toNode.col >= fromNode.col) ? .right : .left
            } else {
                if toNode.col > fromNode.col { resolvedPort = .right }
                else if toNode.col < fromNode.col { resolvedPort = .left }
                else {
                    let hasBottomEdge = edges.contains { $0.fromId == fromId && $0.fromPort == .bottom }
                    resolvedPort = hasBottomEdge ? .right : .bottom
                }
            }
        } else {
            if toNode.row <= fromNode.row {
                resolvedPort = (fromNode.col <= toNode.col) ? .left : .right
            } else {
                if toNode.col > fromNode.col { resolvedPort = .right }
                else if toNode.col < fromNode.col { resolvedPort = .left }
                else {
                    let hasBottomEdge = edges.contains { $0.fromId == fromId && $0.fromPort == .bottom }
                    resolvedPort = hasBottomEdge ? .right : .bottom
                }
            }
        }

        let edgeLabel: String
        if !label.isEmpty {
            edgeLabel = label
        } else if fromNode.type == .decision {
            edgeLabel = (resolvedPort == .bottom) ? "ja" : "nein"
        } else {
            edgeLabel = ""
        }

        edges.append(PAPEdge(fromId: fromId, toId: toId, label: edgeLabel, fromPort: resolvedPort))
    }

    func updateEdge(id: UUID, label: String, port: PAPBranchPort) {
        if let idx = edges.firstIndex(where: { $0.id == id }) {
            pushUndo()
            edges[idx].label = label
            edges[idx].fromPort = port
        }
    }

    func deleteSelected() {
        guard let id = selectedId else { return }
        pushUndo()
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.fromId == id || $0.toId == id }
        selectedId = nil
    }

    func deleteEdge(id: UUID) {
        pushUndo()
        edges.removeAll { $0.id == id }
    }

    func setEdgeLabel(id: UUID, label: String) {
        if let idx = edges.firstIndex(where: { $0.id == id }) {
            pushUndo()
            edges[idx].label = label
        }
    }

    // MARK: Template Loading

    func loadTemplate(_ template: PAPTemplate) {
        pushUndo()
        nodes.removeAll()
        edges.removeAll()

        switch template {
        case .linear:
            let n1 = PAPNode(type: .start,   label: "Start",             col: 1, row: 0)
            let n2 = PAPNode(type: .io,      label: "Zahl x einlesen",   col: 1, row: 1, tag: "E")
            let n3 = PAPNode(type: .process, label: "Ergebnis = x * 2",  col: 1, row: 2)
            let n4 = PAPNode(type: .io,      label: "Ergebnis ausgeben", col: 1, row: 3, tag: "A")
            let n5 = PAPNode(type: .end,     label: "Ende",              col: 1, row: 4)
            nodes = [n1, n2, n3, n4, n5]
            edges = [
                PAPEdge(fromId: n1.id, toId: n2.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n2.id, toId: n3.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n3.id, toId: n4.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n4.id, toId: n5.id, label: "", fromPort: .bottom),
            ]

        case .ifElse:
            let n1 = PAPNode(type: .start,    label: "Start",              col: 1, row: 0)
            let n2 = PAPNode(type: .io,       label: "Alter einlesen",     col: 1, row: 1, tag: "E")
            let n3 = PAPNode(type: .decision, label: "Alter >= 18?",       col: 1, row: 2)
            let n4 = PAPNode(type: .io,       label: "Status: Volljährig", col: 1, row: 3, tag: "A")
            let n5 = PAPNode(type: .io,       label: "Status: Minderjährig",col: 2, row: 3, tag: "A")
            let n6 = PAPNode(type: .end,      label: "Ende",              col: 1, row: 4)
            nodes = [n1, n2, n3, n4, n5, n6]
            edges = [
                PAPEdge(fromId: n1.id, toId: n2.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n2.id, toId: n3.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n3.id, toId: n4.id, label: "ja", fromPort: .bottom),
                PAPEdge(fromId: n3.id, toId: n5.id, label: "nein", fromPort: .right),
                PAPEdge(fromId: n4.id, toId: n6.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n5.id, toId: n6.id, label: "", fromPort: .bottom),
            ]

        case .whileLoop:
            let n1 = PAPNode(type: .start,    label: "Start",          col: 1, row: 0)
            let n2 = PAPNode(type: .process,  label: "i = 0",          col: 1, row: 1)
            let n3 = PAPNode(type: .decision, label: "i < 10?",        col: 1, row: 2)
            let n4 = PAPNode(type: .process,  label: "i = i + 1",      col: 1, row: 3)
            let n5 = PAPNode(type: .io,       label: "Fertig melden",  col: 2, row: 3, tag: "A")
            let n6 = PAPNode(type: .end,      label: "Ende",           col: 2, row: 4)
            nodes = [n1, n2, n3, n4, n5, n6]
            edges = [
                PAPEdge(fromId: n1.id, toId: n2.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n2.id, toId: n3.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n3.id, toId: n4.id, label: "ja", fromPort: .bottom),
                PAPEdge(fromId: n4.id, toId: n3.id, label: "", fromPort: .left), // Loopback to condition
                PAPEdge(fromId: n3.id, toId: n5.id, label: "nein", fromPort: .right),
                PAPEdge(fromId: n5.id, toId: n6.id, label: "", fromPort: .bottom),
            ]

        case .doWhileLoop:
            let n1 = PAPNode(type: .start,    label: "Start",              col: 1, row: 0)
            let n2 = PAPNode(type: .io,       label: "PIN eingeben",       col: 1, row: 1, tag: "E")
            let n3 = PAPNode(type: .decision, label: "PIN korrekt?",       col: 1, row: 2)
            let n4 = PAPNode(type: .process,  label: "Zugriff gewähren",   col: 2, row: 3)
            let n5 = PAPNode(type: .end,      label: "Ende",               col: 2, row: 4)
            nodes = [n1, n2, n3, n4, n5]
            edges = [
                PAPEdge(fromId: n1.id, toId: n2.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n2.id, toId: n3.id, label: "", fromPort: .bottom),
                PAPEdge(fromId: n3.id, toId: n2.id, label: "nein", fromPort: .left), // Loopback up
                PAPEdge(fromId: n3.id, toId: n4.id, label: "ja", fromPort: .right),
                PAPEdge(fromId: n4.id, toId: n5.id, label: "", fromPort: .bottom),
            ]

        case .empty:
            let n1 = PAPNode(type: .start, label: "Start", col: 1, row: 0)
            nodes = [n1]
            edges = []
        }
        selectedId = nodes.first?.id
    }

    // MARK: High-Res Export

    func renderToImage(drawing: PKDrawing? = nil) -> UIImage? {
        guard !nodes.isEmpty else { return nil }
        let pad: CGFloat = 60
        let minX = (nodes.map { $0.cx - $0.type.defaultWidth / 2 }.min() ?? 0) - pad
        let minY = (nodes.map { $0.cy - $0.type.defaultHeight / 2 }.min() ?? 0) - pad
        let maxX = (nodes.map { $0.cx + $0.type.defaultWidth / 2 }.max() ?? 600) + pad
        let maxY = (nodes.map { $0.cy + $0.type.defaultHeight / 2 }.max() ?? 800) + pad
        let w = max(maxX - minX, 300)
        let h = max(maxY - minY, 300)

        let offset = CGPoint(x: -minX, y: -minY)
        let renderView = PAPExportRenderView(nodes: nodes, edges: edges, offset: offset)
            .frame(width: w, height: h)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 2.5
        guard let baseImage = renderer.uiImage else { return nil }

        if let drawing = drawing, !drawing.bounds.isNull && !drawing.strokes.isEmpty {
            let drawingImage = drawing.image(from: CGRect(x: minX, y: minY, width: w, height: h), scale: 2.5)
            let finalRenderer = UIGraphicsImageRenderer(size: baseImage.size)
            return finalRenderer.image { _ in
                baseImage.draw(at: .zero)
                drawingImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
            }
        }
        return baseImage
    }
}

// MARK: - Node View

struct PAPNodeCardView: View {
    let node: PAPNode
    let isSelected: Bool
    let isConnectSource: Bool
    var isConnectTarget: Bool = false

    var body: some View {
        ZStack {
            // Background fill
            nodeShape
                .fill(node.type.fillColor)

            // Crisp border
            nodeShape
                .stroke(
                    isConnectSource ? Color.purple : (isConnectTarget ? Color.blue : (isSelected ? Color.blue : node.type.strokeColor)),
                    style: StrokeStyle(lineWidth: (isSelected || isConnectSource || isConnectTarget) ? 3 : 1.8, dash: isConnectTarget ? [5, 3] : [])
                )

            // IO Tag badge (E for Input, A for Output)
            if node.type == .io && !node.tag.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text(node.tag)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(node.type.strokeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(.leading, 18)
                            .padding(.bottom, 4)
                        Spacer()
                    }
                }
            }

            // Node Text
            Text(node.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(white: 0.12))
                .padding(.horizontal, node.type == .io ? 24 : (node.type == .decision ? 18 : 10))
                .padding(.vertical, 4)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(width: node.type.defaultWidth, height: node.type.defaultHeight)
        .overlay(alignment: .topTrailing) {
            if isConnectSource {
                Text("Start")
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -10)
            } else if isConnectTarget {
                HStack(spacing: 2) {
                    Image(systemName: "plus.circle.fill")
                    Text("Ziel")
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .offset(x: 8, y: -10)
            }
        }
        .shadow(color: isConnectSource ? Color.purple.opacity(0.4) : (isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.08)), radius: (isSelected || isConnectSource) ? 6 : 2, x: 0, y: 2)
    }

    var nodeShape: AnyShape {
        switch node.type {
        case .start, .end:
            return AnyShape(Capsule())
        case .process:
            return AnyShape(RoundedRectangle(cornerRadius: 5))
        case .io:
            return AnyShape(ParallelogramShape())
        case .decision:
            return AnyShape(DiamondShape())
        case .subroutine:
            return AnyShape(SubroutineShape())
        case .connector:
            return AnyShape(Circle())
        }
    }
}

// AnyShape wrapper for type-erased shapes
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { _path = shape.path(in:) }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

// MARK: - Export Render View

struct PAPExportRenderView: View {
    let nodes: [PAPNode]
    let edges: [PAPEdge]
    let offset: CGPoint

    var body: some View {
        ZStack {
            // Render Edges
            ForEach(edges) { edge in
                if let from = nodes.first(where: { $0.id == edge.fromId }),
                   let to   = nodes.first(where: { $0.id == edge.toId }) {
                    let route = OrthogonalRoutingEngine.route(from: from, to: to, fromPort: edge.fromPort)
                    let offsetPoints = route.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
                    let offsetLabel = CGPoint(x: route.labelPos.x + offset.x, y: route.labelPos.y + offset.y)

                    ZStack {
                        OrthogonalEdgeShape(points: offsetPoints, arrowDir: route.arrowDir)
                            .stroke(Color(white: 0.2), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                        if !edge.label.isEmpty {
                            Text(edge.label)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(white: 0.25))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .position(offsetLabel)
                        }
                    }
                }
            }

            // Render Nodes
            ForEach(nodes) { node in
                PAPNodeCardView(node: node, isSelected: false, isConnectSource: false)
                    .position(x: node.cx + offset.x, y: node.cy + offset.y)
            }
        }
    }
}

// MARK: - PencilKit Transparent Canvas for Annotations

final class PAPCanvasView: PKCanvasView {
    var isDrawingMode: Bool = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let touches = event?.allTouches else { return super.hitTest(point, with: event) }
        let hasPencil = touches.contains { $0.type == .pencil }
        if hasPencil || isDrawingMode {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}

struct PAPDrawingCanvasView: UIViewRepresentable {
    @Binding var canvasViewRef: PAPCanvasView?
    let isDrawingMode: Bool

    func makeUIView(context: Context) -> PAPCanvasView {
        let cv = PAPCanvasView()
        cv.backgroundColor = .clear
        cv.isOpaque = false
        cv.drawingPolicy = .anyInput
        cv.tool = PKInkingTool(.pen, color: .black, width: 3)
        cv.isDrawingMode = isDrawingMode
        DispatchQueue.main.async { canvasViewRef = cv }
        return cv
    }

    func updateUIView(_ uiView: PAPCanvasView, context: Context) {
        uiView.isDrawingMode = isDrawingMode
    }
}

// MARK: - Main Designer View

struct PAPDesignerView: View {
    @StateObject private var vm = PAPDesignerViewModel()
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var canvasView: PAPCanvasView?
    @State private var isDrawingMode: Bool = false
    @State private var activeTool: CanvasToolType = .pen
    @State private var selectedPenColor: Color = .black
    @State private var selectedWidth: CGFloat = 3.0
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var rulerActive: Bool = false

    // Dragging state for live snapping
    @State private var draggingNodeId: UUID? = nil
    @State private var dragCurrentCol: Int = 1
    @State private var dragCurrentRow: Int = 0

    // Text & Edge Editing
    @State private var editingNode: PAPNode? = nil
    @State private var editingEdge: PAPEdge? = nil
    @State private var editText: String = ""
    @State private var selectedEdgePort: PAPBranchPort = .bottom
    @State private var showTextEditor: Bool = false
    @State private var selectedTag: String = "E"

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left Toolbar / Shape & Template Palette
                leftPalette
                    .frame(width: 130)
                    .background(Color(.systemGroupedBackground))

                Divider()

                // Interactive Canvas
                mainCanvas
            }
            .navigationTitle("PAP-Designer (DIN 66001)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showTextEditor) {
                textEditorSheet
            }
        }
    }

    // MARK: - Left Palette

    var leftPalette: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Vorlagen
                Menu {
                    ForEach(PAPTemplate.allCases) { t in
                        Button {
                            vm.loadTemplate(t)
                        } label: {
                            Label(t.rawValue, systemImage: t.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("Vorlagen")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)

                Divider().padding(.horizontal, 4)

                // Verbindungen & Sprünge ohne Baustein
                Text("Verbindungen")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                Button {
                    vm.connectMode.toggle()
                    if !vm.connectMode {
                        vm.connectFromId = nil
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: vm.connectMode ? "link.circle.fill" : "link")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(vm.connectMode ? .white : .purple)
                        Text(vm.connectMode ? "Verbinden aktiv" : "Linie verbinden")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(vm.connectMode ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(vm.connectMode ? Color.purple : Color.purple.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                Divider().padding(.horizontal, 4)

                Text("Formen einfügen")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                ForEach(PAPShapeType.allCases) { type in
                    Button {
                        vm.addNode(type: type)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(type.strokeColor)
                            Text(type.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(type.fillColor.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(type.strokeColor.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Divider().padding(.horizontal, 4)

                // Grid Guides Toggle
                Button {
                    vm.showGridGuides.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: vm.showGridGuides ? "grid" : "grid.circle")
                        Text(vm.showGridGuides ? "Spalten: An" : "Spalten: Aus")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Main Interactive Canvas

    var mainCanvas: some View {
        ZStack(alignment: .top) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid & Column Background
                    gridBackground
                        .frame(width: 1600, height: 2600)

                    // Orthogonal Edges
                    ForEach(vm.edges) { edge in
                        edgeView(edge)
                    }

                    // Nodes
                    ForEach(vm.nodes) { node in
                        nodeItemView(node)
                    }

                    // Quick Action HUD on Selected Node
                    if let selected = vm.selectedNode, !isDrawingMode {
                        quickActionHUD(for: selected)
                    }
                }
                .frame(width: 1600, height: 2600)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !vm.connectMode {
                        vm.selectedId = nil
                    }
                }
            }

            // Connect Mode Banner
            if vm.connectMode {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))

                    if let fromId = vm.connectFromId, let fromNode = vm.nodes.first(where: { $0.id == fromId }) {
                        Text("Start: „\(fromNode.label)“ ➔ Zielblock antippen")
                            .font(.subheadline.bold())

                        Button("Start ändern") {
                            vm.connectFromId = nil
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Capsule())
                    } else {
                        Text("1. Start-Block antippen (Verbindung / Sprung ohne Baustein)")
                            .font(.subheadline.bold())
                    }

                    Button("Abbrechen") {
                        vm.connectMode = false
                        vm.connectFromId = nil
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.purple)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .padding(.top, 12)
            }

            // Transparent Drawing Layer
            PAPDrawingCanvasView(canvasViewRef: $canvasView, isDrawingMode: isDrawingMode)

            // Pen Toolbar (when drawing mode is active)
            if isDrawingMode {
                PenToolbarView(
                    activeTool: $activeTool,
                    selectedColor: $selectedPenColor,
                    selectedWidth: $selectedWidth,
                    eraserType: $eraserType,
                    rulerActive: $rulerActive,
                    darkDrawingMode: false,
                    showRuler: true
                ) { newTool in
                    canvasView?.tool = newTool
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Grid Background with Column Guides

    var gridBackground: some View {
        Canvas { ctx, size in
            // Subtle fine dot grid
            let dotStep: CGFloat = 25
            var dx: CGFloat = 0
            while dx < size.width {
                var dy: CGFloat = 0
                while dy < size.height {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dx - 1, y: dy - 1, width: 2, height: 2)),
                        with: .color(Color(white: 0.85))
                    )
                    dy += dotStep
                }
                dx += dotStep
            }

            // Column Guides
            if vm.showGridGuides {
                for col in 0...5 {
                    let colX = PAPGrid.center(col: col, row: 0).x
                    var line = Path()
                    line.move(to: CGPoint(x: colX, y: 0))
                    line.addLine(to: CGPoint(x: colX, y: size.height))
                    ctx.stroke(
                        line,
                        with: .color(col == 1 ? Color.blue.opacity(0.25) : Color.gray.opacity(0.18)),
                        style: StrokeStyle(lineWidth: col == 1 ? 1.5 : 1.0, dash: [4, 4])
                    )
                }
            }
        }
        .background(Color(white: 0.98))
        .overlay(alignment: .topLeading) {
            if vm.showGridGuides {
                HStack(spacing: 0) {
                    ForEach(0...4, id: \.self) { col in
                        let title: String = {
                            switch col {
                            case 0: return "← Zweig Links"
                            case 1: return "Hauptprogramm (Start ↓)"
                            case 2: return "Zweig Rechts 1 →"
                            case 3: return "Zweig Rechts 2 →"
                            default: return "Spalte \(col)"
                            }
                        }()
                        Text(title)
                            .font(.system(size: 11, weight: col == 1 ? .bold : .medium))
                            .foregroundColor(col == 1 ? .blue : .secondary)
                            .frame(width: PAPGrid.colWidth, alignment: .center)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, PAPGrid.originX - PAPGrid.colWidth - PAPGrid.colWidth / 2)
            }
        }
    }

    // MARK: - Node Item View

    func nodeItemView(_ node: PAPNode) -> some View {
        let isSelected = vm.selectedId == node.id
        let isConnect = vm.connectFromId == node.id
        let isTarget = vm.connectMode && vm.connectFromId != nil && vm.connectFromId != node.id
        let isBeingDragged = draggingNodeId == node.id

        let currentPos: CGPoint = {
            if isBeingDragged {
                return PAPGrid.center(col: dragCurrentCol, row: dragCurrentRow)
            }
            return CGPoint(x: node.cx, y: node.cy)
        }()

        return PAPNodeCardView(node: node, isSelected: isSelected, isConnectSource: isConnect, isConnectTarget: isTarget)
            .position(currentPos)
            .onTapGesture {
                vm.tapNode(id: node.id)
            }
            .onLongPressGesture {
                openTextEditor(for: node)
            }
            .gesture(
                DragGesture()
                    .onChanged { val in
                        if !isDrawingMode && !vm.connectMode {
                            draggingNodeId = node.id
                            let grid = PAPGrid.nearestGrid(from: val.location)
                            dragCurrentCol = grid.col
                            dragCurrentRow = grid.row
                        }
                    }
                    .onEnded { _ in
                        if draggingNodeId == node.id {
                            vm.moveNode(id: node.id, toCol: dragCurrentCol, toRow: dragCurrentRow)
                            draggingNodeId = nil
                        }
                    }
            )
    }

    // MARK: - Quick Action HUD (Bedienung wie PAP Designer)

    func quickActionHUD(for node: PAPNode) -> some View {
        let pos = CGPoint(x: node.cx, y: node.cy + node.type.defaultHeight / 2 + 30)

        return HStack(spacing: 6) {
            if node.type == .decision {
                // 1. Straight Down (Ja)
                Button {
                    vm.insertBelow(fromNode: node, type: .process, label: "Ja-Zweig")
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text("Ja")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                // 2. Rechts (Menü für nach unten & nach oben)
                Menu {
                    Button {
                        vm.branchRight(fromDecision: node, type: .process, label: "Nein-Zweig", edgeLabel: "nein", goUp: false)
                    } label: {
                        Label("Rechts nach unten (↓)", systemImage: "arrow.down.right")
                    }

                    Button {
                        vm.branchRight(fromDecision: node, type: .process, label: "Schleife", edgeLabel: "nein", goUp: true)
                    } label: {
                        Label("Rechts nach oben (↑ Schleife)", systemImage: "arrow.up.right")
                    }

                    Divider()

                    Button {
                        vm.connectMode = true
                        vm.connectFromId = node.id
                    } label: {
                        Label("Rechts zu bestehendem Block verbinden…", systemImage: "arrow.turn.up.right")
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                        Text("Rechts")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                // 3. Links (Menü für nach unten & nach oben)
                Menu {
                    Button {
                        vm.branchLeft(fromDecision: node, type: .process, label: "Nein-Zweig", edgeLabel: "nein", goUp: false)
                    } label: {
                        Label("Links nach unten (↓)", systemImage: "arrow.down.left")
                    }

                    Button {
                        vm.branchLeft(fromDecision: node, type: .process, label: "Schleife", edgeLabel: "nein", goUp: true)
                    } label: {
                        Label("Links nach oben (↑ Schleife)", systemImage: "arrow.up.left")
                    }

                    Divider()

                    Button {
                        vm.connectMode = true
                        vm.connectFromId = node.id
                    } label: {
                        Label("Links zu bestehendem Block verbinden…", systemImage: "arrow.turn.up.left")
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.left")
                        Text("Links")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.95))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                // 4. Schnelltasten für Schleife nach oben
                Button {
                    vm.branchRight(fromDecision: node, type: .process, label: "Schleife", edgeLabel: "nein", goUp: true)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                        Text("↗")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Rechts nach oben abzweigen")

                Button {
                    vm.branchLeft(fromDecision: node, type: .process, label: "Schleife", edgeLabel: "nein", goUp: true)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.left")
                        Text("↖")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Links nach oben abzweigen")
            } else {
                // Standard block: Insert menu (below and above)
                Menu {
                    Section("Darunter einfügen (↓)") {
                        Button { vm.insertBelow(fromNode: node, type: .process, label: "Anweisung") } label: {
                            Label("Prozess (Anweisung)", systemImage: "rectangle")
                        }
                        Button { vm.insertBelow(fromNode: node, type: .io, label: "Eingabe", tag: "E") } label: {
                            Label("Eingabe (E)", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        Button { vm.insertBelow(fromNode: node, type: .io, label: "Ausgabe", tag: "A") } label: {
                            Label("Ausgabe (A)", systemImage: "arrow.up.right.and.arrow.down.left")
                        }
                        Button { vm.insertBelow(fromNode: node, type: .decision, label: "Bedingung?") } label: {
                            Label("Verzweigung (Raute)", systemImage: "diamond")
                        }
                        Button { vm.insertBelow(fromNode: node, type: .subroutine, label: "Unterprogramm()") } label: {
                            Label("Unterprogramm", systemImage: "rectangle.split.3x1")
                        }
                        Button { vm.insertBelow(fromNode: node, type: .end, label: "Ende") } label: {
                            Label("Ende / Stopp", systemImage: "oval")
                        }
                    }

                    Section("Darüber einfügen (↑)") {
                        Button { vm.insertAbove(fromNode: node, type: .process, label: "Anweisung") } label: {
                            Label("Prozess darüber", systemImage: "rectangle")
                        }
                        Button { vm.insertAbove(fromNode: node, type: .io, label: "Eingabe", tag: "E") } label: {
                            Label("Eingabe darüber", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        Button { vm.insertAbove(fromNode: node, type: .decision, label: "Bedingung?") } label: {
                            Label("Verzweigung darüber", systemImage: "diamond")
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                        Text("Einfügen")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }

            // Verbinden / Überspringen Menü (Ohne neuen Baustein)
            Menu {
                Section("Verbindungs-Modus") {
                    Button {
                        vm.connectMode = true
                        vm.connectFromId = node.id
                    } label: {
                        Label("Frei mit Zielblock verbinden…", systemImage: "link")
                    }
                }

                let otherNodes = vm.nodes.filter { $0.id != node.id }
                if !otherNodes.isEmpty {
                    Section("Direktsprung zu Block (ohne Baustein)") {
                        ForEach(otherNodes) { target in
                            Button {
                                vm.connect(fromId: node.id, toId: target.id)
                            } label: {
                                let dirHint: String = {
                                    if target.row > node.row { return "↓ Schritt überspringen nach Zeile \(target.row + 1)" }
                                    else if target.row < node.row { return "↑ Rücksprung nach Zeile \(target.row + 1)" }
                                    else { return "→ Quersprung Spalte \(target.col)" }
                                }()
                                Label("\(target.label.isEmpty ? target.type.title : target.label) (\(dirHint))", systemImage: target.type.icon)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                    Text("Verbinden")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.purple)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }

            // Edit
            Button {
                openTextEditor(for: node)
            } label: {
                Image(systemName: "pencil")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }

            // Delete
            Button(role: .destructive) {
                vm.deleteSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.caption2.bold())
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(4)
        .background(Color(.systemBackground).opacity(0.95))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .position(pos)
    }

    // MARK: - Edge View

    func edgeView(_ edge: PAPEdge) -> some View {
        guard let from = vm.nodes.first(where: { $0.id == edge.fromId }),
              let to   = vm.nodes.first(where: { $0.id == edge.toId }) else {
            return AnyView(EmptyView())
        }

        let route = OrthogonalRoutingEngine.route(from: from, to: to, fromPort: edge.fromPort)

        return AnyView(
            ZStack {
                OrthogonalEdgeShape(points: route.points, arrowDir: route.arrowDir)
                    .stroke(Color(white: 0.22), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                if !edge.label.isEmpty {
                    Text(edge.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(white: 0.25))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(white: 0.8), lineWidth: 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .position(route.labelPos)
                        .onTapGesture {
                            openEdgeEditor(edge)
                        }
                }

                // Small tap area to edit/delete connection
                Color.clear
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
                    .position(route.labelPos)
                    .onTapGesture {
                        openEdgeEditor(edge)
                    }
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button("Abbrechen") { dismiss() }

            Button {
                if let cv = canvasView, cv.undoManager?.canUndo == true {
                    cv.undoManager?.undo()
                } else {
                    vm.undo()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!vm.canUndo && (canvasView?.undoManager?.canUndo != true))
            .accessibilityLabel("Rückgängig")

            Button {
                if let cv = canvasView, cv.undoManager?.canRedo == true {
                    cv.undoManager?.redo()
                } else {
                    vm.redo()
                }
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!vm.canRedo && (canvasView?.undoManager?.canRedo != true))
            .accessibilityLabel("Wiederholen")
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                isDrawingMode.toggle()
            } label: {
                Label(isDrawingMode ? "Notizen aktiv" : "Notizen",
                      systemImage: isDrawingMode ? "pencil.and.scribble" : "pencil")
            }
            .tint(isDrawingMode ? .blue : .primary)

            Button("Einfügen") {
                if let img = vm.renderToImage(drawing: canvasView?.drawing) {
                    onInsert(img)
                    dismiss()
                }
            }
            .bold()
            .disabled(vm.nodes.isEmpty)
        }
    }

    // MARK: - Text Editing Helpers

    func openTextEditor(for node: PAPNode) {
        editingNode = node
        editingEdge = nil
        editText = node.label
        selectedTag = node.tag.isEmpty ? "E" : node.tag
        showTextEditor = true
    }

    func openEdgeEditor(_ edge: PAPEdge) {
        editingEdge = edge
        editingNode = nil
        editText = edge.label
        selectedEdgePort = edge.fromPort
        showTextEditor = true
    }

    var textEditorSheet: some View {
        NavigationStack {
            Form {
                if let node = editingNode {
                    Section("Block-Beschriftung") {
                        TextField("Text eingeben", text: $editText)
                            .font(.body)

                        if node.type == .io {
                            Picker("Typ", selection: $selectedTag) {
                                Text("Eingabe (E)").tag("E")
                                Text("Ausgabe (A)").tag("A")
                                Text("Ohne Kennzeichnung").tag("")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                } else if let _ = editingEdge {
                    Section("Ausgangs-Richtung (Port)") {
                        Picker("Ausgang", selection: $selectedEdgePort) {
                            ForEach(PAPBranchPort.allCases) { port in
                                Text(port.title).tag(port)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Verbindungs-Beschriftung") {
                        TextField("z.B. ja, nein, wahr, falsch, überspringen", text: $editText)
                        HStack(spacing: 4) {
                            Button("ja") { editText = "ja" }
                            Button("nein") { editText = "nein" }
                            Button("wahr") { editText = "wahr" }
                            Button("falsch") { editText = "falsch" }
                            Button("überspringen") { editText = "überspringen" }
                            Button("Leeren") { editText = "" }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }

                    Section {
                        Button("Verbindung löschen", role: .destructive) {
                            if let e = editingEdge {
                                vm.deleteEdge(id: e.id)
                            }
                            showTextEditor = false
                        }
                    }
                }
            }
            .navigationTitle(editingNode != nil ? "Block bearbeiten" : "Verbindung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showTextEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let n = editingNode, let idx = vm.nodes.firstIndex(where: { $0.id == n.id }) {
                            vm.pushUndo()
                            vm.nodes[idx].label = editText
                            if n.type == .io { vm.nodes[idx].tag = selectedTag }
                        } else if let e = editingEdge {
                            vm.updateEdge(id: e.id, label: editText, port: selectedEdgePort)
                        }
                        showTextEditor = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.48), .medium])
    }
}
