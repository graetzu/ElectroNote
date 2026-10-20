import SwiftUI
import PencilKit
import UIKit

// MARK: - Bubble Shapes

enum BubbleShape: String, CaseIterable, Identifiable {
    case circle    = "Kreis"
    case oval      = "Oval"
    case rectangle = "Rechteck"
    case diamond   = "Raute"
    case cloud     = "Wolke"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .circle:    return "circle"
        case .oval:      return "capsule"
        case .rectangle: return "rectangle"
        case .diamond:   return "diamond"
        case .cloud:     return "cloud"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .circle:    return 130
        case .oval:      return 160
        case .rectangle: return 150
        case .diamond:   return 140
        case .cloud:     return 170
        }
    }

    var defaultHeight: CGFloat {
        switch self {
        case .circle:    return 130
        case .oval:      return 95
        case .rectangle: return 90
        case .diamond:   return 110
        case .cloud:     return 108
        }
    }

    var shapeKind: String {
        switch self {
        case .circle:    return "CIRCLE"
        case .oval:      return "OVAL"
        case .rectangle: return "RECTANGLE"
        case .diamond:   return "DIAMOND"
        case .cloud:     return "CLOUD"
        }
    }

    static func fromShapeKind(_ kind: String) -> BubbleShape {
        switch kind.uppercased() {
        case "CIRCLE":    return .circle
        case "OVAL":      return .oval
        case "RECTANGLE": return .rectangle
        case "DIAMOND":   return .diamond
        case "CLOUD":     return .cloud
        default:          return .circle
        }
    }
}

// MARK: - Cloud Shape

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY
        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * w, y: y0 + ny * h)
        }

        var p = Path()
        // Start at bottom-left base of cloud
        p.move(to: pt(0.22, 0.84))

        // Left puff
        p.addCurve(
            to: pt(0.14, 0.44),
            control1: pt(0.03, 0.83),
            control2: pt(0.01, 0.52)
        )
        // Top-left puff
        p.addCurve(
            to: pt(0.38, 0.20),
            control1: pt(0.14, 0.24),
            control2: pt(0.27, 0.14)
        )
        // Top-center main puff
        p.addCurve(
            to: pt(0.68, 0.22),
            control1: pt(0.45, 0.04),
            control2: pt(0.63, 0.05)
        )
        // Top-right puff
        p.addCurve(
            to: pt(0.88, 0.46),
            control1: pt(0.79, 0.14),
            control2: pt(0.91, 0.28)
        )
        // Right puff
        p.addCurve(
            to: pt(0.78, 0.84),
            control1: pt(0.99, 0.54),
            control2: pt(0.96, 0.83)
        )
        // Bottom-right to bottom-center puff
        p.addCurve(
            to: pt(0.50, 0.86),
            control1: pt(0.72, 0.94),
            control2: pt(0.58, 0.94)
        )
        // Bottom-center to bottom-left puff
        p.addCurve(
            to: pt(0.22, 0.84),
            control1: pt(0.42, 0.94),
            control2: pt(0.28, 0.94)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Arrow Style

enum MindMapArrowStyle: String, CaseIterable, Identifiable {
    case none    = "ARROW_NONE"
    case forward = "ARROW_FORWARD"
    case both    = "ARROW_BOTH"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:    return "Linie"
        case .forward: return "Pfeil →"
        case .both:    return "Doppel ↔"
        }
    }

    var symbolName: String {
        switch self {
        case .none:    return "line.diagonal"
        case .forward: return "arrow.right"
        case .both:    return "arrow.left.and.right"
        }
    }

    static func fromPortString(_ raw: String) -> MindMapArrowStyle {
        switch raw.uppercased() {
        case "ARROW_NONE", "NONE":       return .none
        case "ARROW_BOTH", "BOTH":       return .both
        case "ARROW_FORWARD", "FORWARD": return .forward
        default:                         return .forward
        }
    }
}

// MARK: - MindMap Models

struct MindMapNode: Identifiable {
    let id: UUID
    var shape: BubbleShape
    var label: String
    var color: Color
    var cx: CGFloat
    var cy: CGFloat

    init(id: UUID = UUID(), shape: BubbleShape, label: String, color: Color = .blue, cx: CGFloat, cy: CGFloat) {
        self.id = id
        self.shape = shape
        self.label = label
        self.color = color
        self.cx = cx
        self.cy = cy
    }

    var boundingRect: CGRect {
        let w = shape.defaultWidth
        let h = shape.defaultHeight
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
}

struct MindMapEdge: Identifiable {
    let id: UUID
    var fromId: UUID
    var toId: UUID
    var label: String
    var arrowStyle: MindMapArrowStyle

    init(
        id: UUID = UUID(),
        fromId: UUID,
        toId: UUID,
        label: String = "",
        arrowStyle: MindMapArrowStyle = .forward
    ) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.label = label
        self.arrowStyle = arrowStyle
    }
}

// MARK: - Smart Branch Routing & Obstacle Avoidance

struct MindMapBranchGeometry {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
    let startTangentAngle: CGFloat // Angle pointing into `start` (for backward arrow)
    let endTangentAngle: CGFloat   // Angle pointing into `end` (for forward arrow)
    let midpoint: CGPoint
    let isOccludedByObstacle: Bool

    var curvePath: Path {
        var p = Path()
        p.move(to: start)
        p.addCurve(to: end, control1: control1, control2: control2)
        return p
    }

    func arrowHeadPath(for style: MindMapArrowStyle, headLength: CGFloat = 13, wingAngle: CGFloat = .pi / 6) -> Path {
        var p = Path()
        if style == .forward || style == .both {
            addArrowWings(to: &p, tip: end, incomingAngle: endTangentAngle, length: headLength, wingAngle: wingAngle)
        }
        if style == .both {
            addArrowWings(to: &p, tip: start, incomingAngle: startTangentAngle, length: headLength, wingAngle: wingAngle)
        }
        return p
    }

    private func addArrowWings(to path: inout Path, tip: CGPoint, incomingAngle: CGFloat, length: CGFloat, wingAngle: CGFloat) {
        let left = CGPoint(
            x: tip.x - length * cos(incomingAngle - wingAngle),
            y: tip.y - length * sin(incomingAngle - wingAngle)
        )
        let right = CGPoint(
            x: tip.x - length * cos(incomingAngle + wingAngle),
            y: tip.y - length * sin(incomingAngle + wingAngle)
        )
        path.move(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
    }

    static func compute(
        from: MindMapNode,
        to: MindMapNode,
        allNodes: [MindMapNode],
        offset: CGPoint = .zero
    ) -> MindMapBranchGeometry {
        let pFrom = CGPoint(x: from.cx + offset.x, y: from.cy + offset.y)
        let pTo   = CGPoint(x: to.cx + offset.x,   y: to.cy + offset.y)

        let obstacles = allNodes.filter { $0.id != from.id && $0.id != to.id }
        let obstacleRects = obstacles.map { n -> CGRect in
            let r = n.boundingRect
            return CGRect(
                x: r.minX + offset.x - 14,
                y: r.minY + offset.y - 14,
                width: r.width + 28,
                height: r.height + 28
            )
        }

        // Determine if any obstacle lies along the direct corridor between `pFrom` and `pTo`
        let dx = pTo.x - pFrom.x
        let dy = pTo.y - pFrom.y
        let dist = max(1, hypot(dx, dy))
        let ux = dx / dist
        let uy = dy / dist
        // Normal vector perpendicular to (pFrom -> pTo)
        let nx = -uy
        let ny = ux

        var blockingObstacles: [(rect: CGRect, signedPerp: CGFloat,clearanceNeeded: CGFloat)] = []
        for rect in obstacleRects {
            if segmentIntersectsOrNearsRect(a: pFrom, b: pTo, rect: rect) {
                let ocx = rect.midX - pFrom.x
                let ocy = rect.midY - pFrom.y
                let signedPerp = ocx * nx + ocy * ny
                let radius = hypot(rect.width / 2, rect.height / 2) + 22
                blockingObstacles.append((rect, signedPerp, radius))
            }
        }

        var deflection: CGFloat = 0
        if !blockingObstacles.isEmpty {
            // Choose the detour side (+normal or -normal) that pushes cleanly past the blocking obstacle(s)
            // If obstacle center has positive `signedPerp`, detour in the negative normal direction (and vice versa)
            let avgSigned = blockingObstacles.map(\.signedPerp).reduce(0, +) / CGFloat(blockingObstacles.count)
            let sideSign: CGFloat = avgSigned >= 0 ? -1.0 : 1.0

            var requiredOffset: CGFloat = 70
            for obs in blockingObstacles {
                // Distance from line to clear this obstacle on `sideSign` side
                let needed = obs.clearanceNeeded - (obs.signedPerp * sideSign)
                if needed > requiredOffset {
                    requiredOffset = needed
                }
            }
            deflection = sideSign * min(max(requiredOffset, 65), 240)
        }

        // Compute virtual target points so perimeter anchors exit/enter toward the curved detour
        let midLinear = CGPoint(x: (pFrom.x + pTo.x) * 0.5, y: (pFrom.y + pTo.y) * 0.5)
        let detourApex = CGPoint(
            x: midLinear.x + nx * deflection,
            y: midLinear.y + ny * deflection
        )

        let aimFrom = abs(deflection) > 1 ? detourApex : pTo
        let aimTo   = abs(deflection) > 1 ? detourApex : pFrom

        let startPt = perimeterPoint(for: from, center: pFrom, toward: aimFrom)
        let endPt   = perimeterPoint(for: to,   center: pTo,   toward: aimTo)

        let c1: CGPoint
        let c2: CGPoint
        if abs(deflection) > 1 {
            c1 = CGPoint(
                x: startPt.x + (detourApex.x - startPt.x) * 0.85,
                y: startPt.y + (detourApex.y - startPt.y) * 0.85
            )
            c2 = CGPoint(
                x: endPt.x + (detourApex.x - endPt.x) * 0.85,
                y: endPt.y + (detourApex.y - endPt.y) * 0.85
            )
        } else {
            let sdx = endPt.x - startPt.x
            let sdy = endPt.y - startPt.y
            if abs(sdx) >= abs(sdy) {
                c1 = CGPoint(x: startPt.x + sdx * 0.45, y: startPt.y)
                c2 = CGPoint(x: startPt.x + sdx * 0.55, y: endPt.y)
            } else {
                c1 = CGPoint(x: startPt.x, y: startPt.y + sdy * 0.45)
                c2 = CGPoint(x: endPt.x,   y: startPt.y + sdy * 0.55)
            }
        }

        // Sample cubic Bezier to check if it still clips any obstacle interior and to get midpoint
        let rawObstacleRects = obstacles.map { n -> CGRect in
            let r = n.boundingRect
            return CGRect(x: r.minX + offset.x + 4, y: r.minY + offset.y + 4, width: max(1, r.width - 8), height: max(1, r.height - 8))
        }
        var stillOccluded = false
        for i in 1..<24 {
            let t = CGFloat(i) / 24.0
            let pt = cubicBezierPoint(t: t, p0: startPt, p1: c1, p2: c2, p3: endPt)
            if rawObstacleRects.contains(where: { $0.contains(pt) }) {
                stillOccluded = true
                break
            }
        }

        let midCurve = cubicBezierPoint(t: 0.5, p0: startPt, p1: c1, p2: c2, p3: endPt)

        // End tangent (from control2 -> endPt; fallback to startPt -> endPt)
        let endDx = (hypot(endPt.x - c2.x, endPt.y - c2.y) > 2) ? (endPt.x - c2.x) : (endPt.x - startPt.x)
        let endDy = (hypot(endPt.x - c2.x, endPt.y - c2.y) > 2) ? (endPt.y - c2.y) : (endPt.y - startPt.y)
        let endAngle = atan2(endDy, endDx)

        // Start tangent (pointing INTO `startPt`, i.e. from control1 -> startPt)
        let startDx = (hypot(startPt.x - c1.x, startPt.y - c1.y) > 2) ? (startPt.x - c1.x) : (startPt.x - endPt.x)
        let startDy = (hypot(startPt.x - c1.x, startPt.y - c1.y) > 2) ? (startPt.y - c1.y) : (startPt.y - endPt.y)
        let startAngle = atan2(startDy, startDx)

        return MindMapBranchGeometry(
            start: startPt,
            control1: c1,
            control2: c2,
            end: endPt,
            startTangentAngle: startAngle,
            endTangentAngle: endAngle,
            midpoint: midCurve,
            isOccludedByObstacle: stillOccluded
        )
    }

    private static func perimeterPoint(for node: MindMapNode, center: CGPoint, toward target: CGPoint) -> CGPoint {
        let dx = target.x - center.x
        let dy = target.y - center.y
        let angle = atan2(dy, dx)
        let rx = node.shape.defaultWidth / 2
        let ry = node.shape.defaultHeight / 2
        guard hypot(dx, dy) > 1 else { return CGPoint(x: center.x + rx, y: center.y) }

        switch node.shape {
        case .circle, .oval, .cloud:
            let scaleFactor: CGFloat = (node.shape == .cloud) ? 0.88 : 1.0
            let px = center.x + rx * scaleFactor * cos(angle)
            let py = center.y + ry * scaleFactor * sin(angle)
            return CGPoint(x: px, y: py)

        case .rectangle:
            let cosA = cos(angle)
            let sinA = sin(angle)
            let tx = abs(cosA) > 0.0001 ? rx / abs(cosA) : .greatestFiniteMagnitude
            let ty = abs(sinA) > 0.0001 ? ry / abs(sinA) : .greatestFiniteMagnitude
            let t = min(tx, ty)
            return CGPoint(x: center.x + t * cosA, y: center.y + t * sinA)

        case .diamond:
            let cosA = cos(angle)
            let sinA = sin(angle)
            // Diamond boundary: |x|/rx + |y|/ry = 1
            let denom = abs(cosA) / rx + abs(sinA) / ry
            let t = denom > 0.0001 ? (1.0 / denom) : rx
            return CGPoint(x: center.x + t * cosA, y: center.y + t * sinA)
        }
    }

    private static func segmentIntersectsOrNearsRect(a: CGPoint, b: CGPoint, rect: CGRect) -> Bool {
        let steps = 20
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
            if rect.contains(p) {
                return true
            }
        }
        return false
    }

    private static func cubicBezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t

        let x = uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x
        let y = uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - MindMap ViewModel

@MainActor
final class MindMapDesignerViewModel: ObservableObject {
    @Published var nodes: [MindMapNode] = []
    @Published var edges: [MindMapEdge] = []
    @Published var selectedId: UUID? = nil
    @Published var selectedEdgeId: UUID? = nil
    @Published var connectMode: Bool = false
    @Published var connectFromId: UUID? = nil
    @Published var defaultArrowStyle: MindMapArrowStyle = .forward

    private var undoStack: [([MindMapNode], [MindMapEdge])] = []
    private var redoStack: [([MindMapNode], [MindMapEdge])] = []

    private var store: DiagramDocumentStore? = nil
    private var diagramId: String = UUID().uuidString
    @Published var diagramName: String = "MindMap"
    private var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { selectedId != nil || selectedEdgeId != nil }

    init() {
        setupLiveCollabHooks()
    }

    func configure(folderURL: URL) {
        let store = DiagramDocumentStore(folderURL: folderURL)
        self.store = store

        if let doc = store.load() {
            applyDTO(doc)
            undoStack.removeAll()
            redoStack.removeAll()
        } else {
            let folderName = folderURL.deletingPathExtension().lastPathComponent
            if !folderName.isEmpty {
                self.diagramName = folderName
            }
            save()
        }
        setupLiveCollabHooks()
    }

    func exportDTO() -> DiagramDocumentDTO {
        let nodeDTOs = nodes.map { n in
            let uiColor = UIColor(n.color)
            return DiagramNodeDTO(
                id: n.id.uuidString,
                x: Double(n.cx - n.shape.defaultWidth / 2),
                y: Double(n.cy - n.shape.defaultHeight / 2),
                shape: n.shape.shapeKind,
                text: n.label,
                color: uiColor.argbInt64,
                col: nil,
                row: nil,
                tag: nil
            )
        }
        let edgeDTOs = edges.map { e in
            DiagramConnectionDTO(
                id: e.id.uuidString,
                fromNodeId: e.fromId.uuidString,
                toNodeId: e.toId.uuidString,
                label: e.label,
                fromPort: e.arrowStyle.rawValue
            )
        }
        return DiagramDocumentDTO(
            id: diagramId,
            name: diagramName,
            type: "mindmap",
            createdAt: createdAt,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
            nodes: nodeDTOs,
            connections: edgeDTOs,
            bypassDistancePx: nil
        )
    }

    func applyDTO(_ doc: DiagramDocumentDTO) {
        self.diagramId = doc.id
        self.diagramName = doc.name
        self.createdAt = doc.createdAt
        self.nodes = doc.nodes.compactMap { dto in
            let shape = BubbleShape.fromShapeKind(dto.shape)
            let id = UUID(uuidString: dto.id) ?? UUID()
            let color = dto.color != nil ? Color(uiColor: UIColor(argbInt: dto.color!)) : .blue
            let cx = CGFloat(dto.x) + shape.defaultWidth / 2
            let cy = CGFloat(dto.y) + shape.defaultHeight / 2
            return MindMapNode(id: id, shape: shape, label: dto.text, color: color, cx: cx, cy: cy)
        }
        self.edges = doc.connections.compactMap { dto in
            guard let fromId = UUID(uuidString: dto.fromNodeId),
                  let toId = UUID(uuidString: dto.toNodeId) else { return nil }
            let id = UUID(uuidString: dto.id) ?? UUID()
            let style = MindMapArrowStyle.fromPortString(dto.fromPort)
            return MindMapEdge(id: id, fromId: fromId, toId: toId, label: dto.label, arrowStyle: style)
        }
    }

    func broadcastCurrentState() {
        let dto = exportDTO()
        if let data = try? JSONEncoder().encode(dto),
           let json = String(data: data, encoding: .utf8) {
            LiveCollabSessionManager.shared.sendDiagramAction(action: .nodeUpdated, nodeJson: json)
        }
    }

    func setupLiveCollabHooks() {
        let collab = LiveCollabSessionManager.shared

        collab.onProvideSnapshot = { [weak self] in
            guard let self = self else { return (nil, nil, nil, nil, nil) }
            let dto = self.exportDTO()
            let data = try? JSONEncoder().encode(dto)
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            return (json, nil, nil, self.diagramName, nil)
        }

        collab.onApplySnapshot = { [weak self] docJson, _, _, _ in
            guard let self = self,
                  let docJson = docJson,
                  let data = docJson.data(using: .utf8),
                  let dto = try? JSONDecoder().decode(DiagramDocumentDTO.self, from: data) else { return }
            self.applyDTO(dto)
            self.store?.save(dto)
        }

        collab.onRemoteDiagramAction = { [weak self] message in
            guard let self = self else { return }
            if let json = message.nodeJson,
               let data = json.data(using: .utf8),
               let dto = try? JSONDecoder().decode(DiagramDocumentDTO.self, from: data) {
                self.applyDTO(dto)
                self.store?.save(dto)
            }
        }
    }

    func save() {
        guard let store = self.store else { return }
        let doc = exportDTO()
        store.save(doc)
    }

    func pushUndo() {
        undoStack.append((nodes, edges))
        redoStack.removeAll()
        save()
        broadcastCurrentState()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append((nodes, edges))
        nodes = prev.0
        edges = prev.1
        selectedId = nil
        selectedEdgeId = nil
        connectFromId = nil
        save()
        broadcastCurrentState()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((nodes, edges))
        nodes = next.0
        edges = next.1
        save()
        broadcastCurrentState()
    }

    func addNode(_ shape: BubbleShape, color: Color, near anchor: CGPoint) {
        pushUndo()
        let defaultLabel: String
        switch shape {
        case .circle:    defaultLabel = "Zentralthema"
        case .oval:      defaultLabel = "Hauptidee"
        case .rectangle: defaultLabel = "Notiz"
        case .diamond:   defaultLabel = "Aspekt"
        case .cloud:     defaultLabel = "Gedanke"
        }
        let node = MindMapNode(shape: shape, label: defaultLabel, color: color, cx: anchor.x, cy: anchor.y)
        nodes.append(node)
        selectedId = node.id
        selectedEdgeId = nil
        save()
        broadcastCurrentState()
    }

    func move(id: UUID, to p: CGPoint) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            nodes[i].cx = p.x
            nodes[i].cy = p.y
        }
    }

    func commitMove() {
        save()
        broadcastCurrentState()
    }

    func tap(id: UUID) {
        if connectMode {
            if let from = connectFromId, from != id {
                if !edges.contains(where: { ($0.fromId == from && $0.toId == id) || ($0.fromId == id && $0.toId == from) }) {
                    pushUndo()
                    let newEdge = MindMapEdge(fromId: from, toId: id, arrowStyle: defaultArrowStyle)
                    edges.append(newEdge)
                    selectedEdgeId = newEdge.id
                    selectedId = nil
                    save()
                    broadcastCurrentState()
                }
                connectFromId = nil
            } else {
                connectFromId = id
            }
        } else {
            selectedEdgeId = nil
            selectedId = (selectedId == id) ? nil : id
        }
    }

    func tapEdge(id: UUID) {
        selectedId = nil
        connectFromId = nil
        selectedEdgeId = (selectedEdgeId == id) ? nil : id
    }

    func deleteSelected() {
        if let nodeId = selectedId {
            pushUndo()
            nodes.removeAll { $0.id == nodeId }
            edges.removeAll { $0.fromId == nodeId || $0.toId == nodeId }
            selectedId = nil
            save()
            broadcastCurrentState()
        } else if let edgeId = selectedEdgeId {
            pushUndo()
            edges.removeAll { $0.id == edgeId }
            selectedEdgeId = nil
            save()
            broadcastCurrentState()
        }
    }

    func setNodeLabel(id: UUID, label: String) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            pushUndo()
            nodes[i].label = label
            save()
            broadcastCurrentState()
        }
    }

    func setNodeColor(id: UUID, color: Color) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            pushUndo()
            nodes[i].color = color
            save()
            broadcastCurrentState()
        }
    }

    func setEdgeArrowStyle(id: UUID, style: MindMapArrowStyle) {
        if let i = edges.firstIndex(where: { $0.id == id }) {
            pushUndo()
            edges[i].arrowStyle = style
            save()
            broadcastCurrentState()
        }
    }

    func reverseEdgeDirection(id: UUID) {
        if let i = edges.firstIndex(where: { $0.id == id }) {
            pushUndo()
            let oldFrom = edges[i].fromId
            edges[i].fromId = edges[i].toId
            edges[i].toId = oldFrom
            save()
            broadcastCurrentState()
        }
    }

    func setEdgeLabel(id: UUID, label: String) {
        if let i = edges.firstIndex(where: { $0.id == id }) {
            pushUndo()
            edges[i].label = label
            save()
            broadcastCurrentState()
        }
    }

    // MARK: Export

    func renderToImage(drawing: PKDrawing? = nil) -> UIImage? {
        guard !nodes.isEmpty else { return nil }
        let pad: CGFloat = 80
        let minX = (nodes.map { $0.cx - $0.shape.defaultWidth / 2  }.min() ?? 0) - pad
        let minY = (nodes.map { $0.cy - $0.shape.defaultHeight / 2 }.min() ?? 0) - pad
        let maxX = (nodes.map { $0.cx + $0.shape.defaultWidth / 2  }.max() ?? 400) + pad
        let maxY = (nodes.map { $0.cy + $0.shape.defaultHeight / 2 }.max() ?? 600) + pad
        let w = max(maxX - minX, 300)
        let h = max(maxY - minY, 300)
        let offset = CGPoint(x: -minX, y: -minY)

        let renderView = MindMapRenderView(nodes: nodes, edges: edges, offset: offset)
            .frame(width: w, height: h)
            .background(Color.white)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 2
        guard let baseImage = renderer.uiImage else { return nil }

        if let drawing = drawing, !drawing.bounds.isNull && !drawing.strokes.isEmpty {
            let drawingImage = drawing.image(from: CGRect(x: minX, y: minY, width: w, height: h), scale: 2)
            let finalRenderer = UIGraphicsImageRenderer(size: baseImage.size)
            return finalRenderer.image { _ in
                baseImage.draw(at: .zero)
                drawingImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
            }
        }
        return baseImage
    }
}

// MARK: - Pure Render View for Export

struct MindMapRenderView: View {
    let nodes: [MindMapNode]
    let edges: [MindMapEdge]
    let offset: CGPoint

    var body: some View {
        ZStack {
            ForEach(edges) { edge in
                edgeBranch(edge)
            }
            ForEach(nodes) { node in
                MindMapBubbleShapeView(node: node, isSelected: false)
                    .position(x: node.cx + offset.x, y: node.cy + offset.y)
            }
        }
    }

    func edgeBranch(_ edge: MindMapEdge) -> some View {
        guard let from = nodes.first(where: { $0.id == edge.fromId }),
              let to   = nodes.first(where: { $0.id == edge.toId }) else {
            return AnyView(EmptyView())
        }
        let geom = MindMapBranchGeometry.compute(from: from, to: to, allNodes: nodes, offset: offset)
        let baseOpacity: Double = geom.isOccludedByObstacle ? 0.25 : 0.85
        let strokeColor = from.color.opacity(baseOpacity)

        return AnyView(
            ZStack {
                geom.curvePath
                    .stroke(
                        strokeColor,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            dash: geom.isOccludedByObstacle ? [7, 5] : []
                        )
                    )
                if edge.arrowStyle != .none {
                    geom.arrowHeadPath(for: edge.arrowStyle)
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if !edge.label.isEmpty {
                    Text(edge.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .position(geom.midpoint)
                }
            }
        )
    }
}

// MARK: - Bubble Shape View

struct MindMapBubbleShapeView: View {
    let node: MindMapNode
    let isSelected: Bool

    var body: some View {
        ZStack {
            shapeBackground
                .frame(width: node.shape.defaultWidth, height: node.shape.defaultHeight)

            Text(node.label.isEmpty ? "Idee..." : node.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, node.shape == .cloud ? 22 : 12)
                .padding(.vertical, node.shape == .cloud ? 14 : 8)
                .frame(
                    maxWidth: node.shape.defaultWidth - (node.shape == .cloud ? 34 : 16),
                    maxHeight: node.shape.defaultHeight - (node.shape == .cloud ? 26 : 16)
                )
        }
    }

    @ViewBuilder
    var shapeBackground: some View {
        // Opaque white under-fill so any unavoidable line passing beneath a shape is softly masked
        let baseFill = Color(white: 0.99)
        let tintFill = node.color.opacity(0.18)
        let stroke = isSelected ? Color.orange : node.color
        let lineWidth: CGFloat = isSelected ? 3.5 : 2.5

        switch node.shape {
        case .circle:
            Circle()
                .fill(baseFill)
                .overlay(Circle().fill(tintFill))
                .overlay(Circle().stroke(stroke, lineWidth: lineWidth))
        case .oval:
            Capsule()
                .fill(baseFill)
                .overlay(Capsule().fill(tintFill))
                .overlay(Capsule().stroke(stroke, lineWidth: lineWidth))
        case .rectangle:
            RoundedRectangle(cornerRadius: 14)
                .fill(baseFill)
                .overlay(RoundedRectangle(cornerRadius: 14).fill(tintFill))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke, lineWidth: lineWidth))
        case .diamond:
            DiamondShape()
                .fill(baseFill)
                .overlay(DiamondShape().fill(tintFill))
                .overlay(DiamondShape().stroke(stroke, lineWidth: lineWidth))
        case .cloud:
            CloudShape()
                .fill(baseFill)
                .overlay(CloudShape().fill(tintFill))
                .overlay(CloudShape().stroke(stroke, lineWidth: lineWidth))
        }
    }
}

// MARK: - Transparent PencilKit Canvas for MindMap Annotations

final class MindMapCanvasView: PKCanvasView {
    var isDrawingMode: Bool = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let touches = event?.allTouches else { return super.hitTest(point, with: event) }
        let hasPencil = touches.contains { $0.type == .pencil }
        if hasPencil || isDrawingMode {
            return super.hitTest(point, with: event)
        }
        // In mindmap mode, pass finger touches through to move/connect nodes
        return nil
    }
}

struct MindMapDrawingCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasViewRef: MindMapCanvasView?
    let isDrawingMode: Bool

    func makeUIView(context: Context) -> MindMapCanvasView {
        let cv = MindMapCanvasView()
        cv.backgroundColor = .clear
        cv.isOpaque = false
        cv.drawingPolicy = .anyInput
        cv.overrideUserInterfaceStyle = .light
        cv.tool = PKInkingTool(.pen, color: .black, width: 3)
        cv.isDrawingMode = isDrawingMode
        DispatchQueue.main.async { canvasViewRef = cv }
        return cv
    }

    func updateUIView(_ uiView: MindMapCanvasView, context: Context) {
        uiView.isDrawingMode = isDrawingMode
    }
}

// MARK: - Main MindMap Designer View

struct MindMapDesignerView: View {
    var item: DocumentItem? = nil
    var onInsert: ((UIImage) -> Void)? = nil
    @StateObject private var vm = MindMapDesignerViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var canvasView: MindMapCanvasView?
    @State private var isDrawingMode: Bool = false
    @State private var activeTool: CanvasToolType = .pen
    @State private var selectedPenColor: Color = .black
    @State private var selectedWidth: CGFloat = 3.0
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var rulerActive: Bool = false

    @State private var selectedBubbleColor: Color = .blue
    @State private var editLabelText = ""
    @State private var showEditLabel = false
    @State private var editingNodeId: UUID? = nil

    @State private var editEdgeLabelText = ""
    @State private var showEditEdgeLabel = false
    @State private var editingEdgeId: UUID? = nil

    private let bubbleColors: [Color] = [
        .blue, .purple, .indigo, .teal,
        .green, .mint, .orange, .yellow,
        .pink, .red, .brown, .gray
    ]

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left shapes & actions palette
                shapePalette
                    .frame(width: 108)
                    .background(Color(.systemGroupedBackground))

                Divider()

                // Interactive MindMap canvas
                canvas
            }
            .navigationTitle("MindMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Knoten-Text bearbeiten", isPresented: $showEditLabel) {
                TextField("Text", text: $editLabelText)
                Button("OK") { applyLabelEdit() }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Pfeil-Beschriftung", isPresented: $showEditEdgeLabel) {
                TextField("Beschriftung (optional)", text: $editEdgeLabelText)
                Button("OK") { applyEdgeLabelEdit() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
        .onAppear {
            if let item = item {
                vm.configure(folderURL: item.path)
            }
        }
        .onDisappear {
            vm.save()
        }
        .onChange(of: vm.selectedId) { _, newId in
            if let id = newId, let node = vm.nodes.first(where: { $0.id == id }) {
                selectedBubbleColor = node.color
            }
        }
    }

    // MARK: Shape palette

    var shapePalette: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Formen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                ForEach(BubbleShape.allCases) { shape in
                    Button {
                        vm.addNode(shape, color: selectedBubbleColor, near: CGPoint(x: 260, y: CGFloat(vm.nodes.count) * 115 + 110))
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: shape.symbolName)
                                .font(.title3)
                                .foregroundStyle(selectedBubbleColor)
                            Text(shape.rawValue)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selectedBubbleColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Divider().padding(.vertical, 2)

                // Connect mode toggle
                Button {
                    vm.connectMode.toggle()
                    vm.connectFromId = nil
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: vm.connectMode ? "point.filled.topleft.down.curvedto.point.bottomright.up" : "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.title3)
                            .foregroundStyle(vm.connectMode ? .blue : .primary)
                        Text(vm.connectMode ? "Verbinden\naktiv" : "Verbinden")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(vm.connectMode ? Color.blue.opacity(0.18) : Color(.systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                // Arrow style selector (applies to new connections AND currently selected connection)
                Text("Verbindungstyp")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    ForEach(MindMapArrowStyle.allCases) { style in
                        let currentStyle: MindMapArrowStyle = {
                            if let selEdgeId = vm.selectedEdgeId,
                               let edge = vm.edges.first(where: { $0.id == selEdgeId }) {
                                return edge.arrowStyle
                            }
                            return vm.defaultArrowStyle
                        }()
                        let isActive = (currentStyle == style)

                        Button {
                            vm.defaultArrowStyle = style
                            if let selEdgeId = vm.selectedEdgeId {
                                vm.setEdgeArrowStyle(id: selEdgeId, style: style)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: style.symbolName)
                                    .font(.caption2.weight(.bold))
                                Text(style.title)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.orange.opacity(0.22) : Color(.tertiarySystemFill))
                            .foregroundColor(isActive ? .orange : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)

                Divider().padding(.vertical, 2)

                // Color picker for new AND selected nodes
                Text(vm.selectedId != nil ? "Form-Farbe" : "Farbe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(Array(bubbleColors.enumerated()), id: \.offset) { _, col in
                        Circle()
                            .fill(col)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.65), lineWidth: selectedBubbleColor == col ? 2.5 : 0)
                            )
                            .onTapGesture {
                                applyColorSelection(col)
                            }
                    }
                }
                .padding(.horizontal, 8)

                // Custom ColorPicker
                ColorPicker(
                    "Eigene",
                    selection: Binding(
                        get: { selectedBubbleColor },
                        set: { newCol in applyColorSelection(newCol) }
                    ),
                    supportsOpacity: false
                )
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    private func applyColorSelection(_ color: Color) {
        selectedBubbleColor = color
        if let selectedNodeId = vm.selectedId {
            vm.setNodeColor(id: selectedNodeId, color: color)
        }
    }

    // MARK: Canvas

    var canvas: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                // Subtle dot grid background
                Canvas { ctx, size in
                    let step: CGFloat = 30
                    var x: CGFloat = 15
                    while x < size.width {
                        var y: CGFloat = 15
                        while y < size.height {
                            let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                            ctx.fill(dot, with: .color(Color(white: 0.85)))
                            y += step
                        }
                        x += step
                    }
                }
                .background(Color(white: 0.98))
                .contentShape(Rectangle())
                .onTapGesture {
                    vm.selectedId = nil
                    vm.selectedEdgeId = nil
                    vm.connectFromId = nil
                }

                // Branches / Edges
                ForEach(vm.edges) { edge in
                    edgeBranchView(edge)
                }

                // Node Bubbles
                ForEach(vm.nodes) { node in
                    MindMapBubbleShapeView(
                        node: node,
                        isSelected: vm.selectedId == node.id || vm.connectFromId == node.id
                    )
                    .position(x: node.cx, y: node.cy)
                    .onTapGesture {
                        vm.tap(id: node.id)
                    }
                    .onLongPressGesture {
                        editingNodeId = node.id
                        editLabelText = node.label
                        showEditLabel = true
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                if !vm.connectMode && !isDrawingMode {
                                    vm.move(id: node.id, to: v.location)
                                }
                            }
                            .onEnded { _ in
                                if !vm.connectMode && !isDrawingMode {
                                    vm.commitMove()
                                }
                            }
                    )
                }

                // Connect hint banner
                if vm.connectMode {
                    Text(vm.connectFromId == nil ? "Start-Knoten antippen" : "Ziel-Knoten für Verbindung antippen")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }

                // Selected Edge Action Bar
                if let selEdgeId = vm.selectedEdgeId,
                   let selEdge = vm.edges.first(where: { $0.id == selEdgeId }) {
                    selectedEdgeBanner(selEdge)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity)
                }
            }

            // Transparent PencilKit layer for handwriting notes & sketches
            MindMapDrawingCanvasRepresentable(canvasViewRef: $canvasView, isDrawingMode: isDrawingMode)

            // Top Pen Toolbar
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
        .clipped()
    }

    @ViewBuilder
    private func selectedEdgeBanner(_ edge: MindMapEdge) -> some View {
        HStack(spacing: 10) {
            ForEach(MindMapArrowStyle.allCases) { style in
                Button {
                    vm.setEdgeArrowStyle(id: edge.id, style: style)
                } label: {
                    Label(style.title, systemImage: style.symbolName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(edge.arrowStyle == style ? Color.orange : Color(.secondarySystemFill))
                        .foregroundColor(edge.arrowStyle == style ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if edge.arrowStyle == .forward {
                Button {
                    vm.reverseEdgeDirection(id: edge.id)
                } label: {
                    Label("Richtung ⇄", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                editingEdgeId = edge.id
                editEdgeLabelText = edge.label
                showEditEdgeLabel = true
            } label: {
                Label("Text", systemImage: "character.cursor.ibeam")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                vm.deleteSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    func edgeBranchView(_ edge: MindMapEdge) -> some View {
        guard let from = vm.nodes.first(where: { $0.id == edge.fromId }),
              let to   = vm.nodes.first(where: { $0.id == edge.toId })
        else { return AnyView(EmptyView()) }

        let geom = MindMapBranchGeometry.compute(from: from, to: to, allNodes: vm.nodes)
        let isSelected = (vm.selectedEdgeId == edge.id)
        let baseOpacity: Double = isSelected ? 1.0 : (geom.isOccludedByObstacle ? 0.25 : 0.85)
        let strokeColor: Color = isSelected ? .orange : from.color.opacity(baseOpacity)
        let lineWidth: CGFloat = isSelected ? 4.5 : 3.2

        return AnyView(
            ZStack {
                // Visible curve
                geom.curvePath
                    .stroke(
                        strokeColor,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            dash: (!isSelected && geom.isOccludedByObstacle) ? [7, 5] : []
                        )
                    )

                // Arrowhead(s)
                if edge.arrowStyle != .none {
                    geom.arrowHeadPath(for: edge.arrowStyle, headLength: isSelected ? 15 : 13)
                        .stroke(
                            strokeColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }

                // Wide invisible hit target so tapping an arrow/line is easy
                geom.curvePath
                    .stroke(Color.white.opacity(0.001), lineWidth: 26)
                    .contentShape(geom.curvePath.strokedPath(StrokeStyle(lineWidth: 26, lineCap: .round)))
                    .onTapGesture {
                        vm.tapEdge(id: edge.id)
                    }

                // Midpoint handle or label pill (also tappable)
                if !edge.label.isEmpty || isSelected {
                    HStack(spacing: 4) {
                        if !edge.label.isEmpty {
                            Text(edge.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : .primary)
                        } else if isSelected {
                            Image(systemName: edge.arrowStyle.symbolName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, edge.label.isEmpty ? 6 : 8)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color.orange : Color.white.opacity(0.92), in: Capsule())
                    .overlay(
                        Capsule().stroke(isSelected ? Color.white : from.color.opacity(0.4), lineWidth: 1)
                    )
                    .position(geom.midpoint)
                    .onTapGesture {
                        vm.tapEdge(id: edge.id)
                    }
                }
            }
        )
    }

    // MARK: Toolbar

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
            // Live Collaboration
            LiveCollabBadgeButton(documentName: vm.diagramName, documentType: .mindmap)

            // Edit text button for selected node
            if let sel = vm.selectedId, let node = vm.nodes.first(where: { $0.id == sel }) {
                Button {
                    editingNodeId = node.id
                    editLabelText = node.label
                    showEditLabel = true
                } label: {
                    Label("Text bearbeiten", systemImage: "character.cursor.ibeam")
                }
            }

            // Mode toggle: MindMap vs Freehand Drawing
            Button {
                isDrawingMode.toggle()
            } label: {
                Label(isDrawingMode ? "Notizen aktiv" : "Notizen",
                      systemImage: isDrawingMode ? "pencil.and.scribble" : "pencil")
            }
            .tint(isDrawingMode ? .blue : .primary)

            Button(role: .destructive) { vm.deleteSelected() } label: {
                Image(systemName: "trash")
            }
            .disabled(!vm.hasSelection)

            Button("Einfügen") {
                if let img = vm.renderToImage(drawing: canvasView?.drawing) {
                    onInsert?(img)
                    dismiss()
                }
            }
            .bold()
            .disabled(vm.nodes.isEmpty)
        }
    }

    func applyLabelEdit() {
        if let id = editingNodeId {
            vm.setNodeLabel(id: id, label: editLabelText)
            editingNodeId = nil
        }
    }

    func applyEdgeLabelEdit() {
        if let id = editingEdgeId {
            vm.setEdgeLabel(id: id, label: editEdgeLabelText)
            editingEdgeId = nil
        }
    }
}
