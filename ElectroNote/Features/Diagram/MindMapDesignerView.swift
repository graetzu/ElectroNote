import SwiftUI
import PencilKit
import UIKit

// MARK: - Bubble Shapes

enum BubbleShape: String, CaseIterable, Identifiable {
    case circle    = "Kreis"
    case oval      = "Oval"
    case rectangle = "Rechteck"
    case diamond   = "Raute"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .circle:    return "circle"
        case .oval:      return "capsule"
        case .rectangle: return "rectangle"
        case .diamond:   return "diamond"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .circle:    return 130
        case .oval:      return 160
        case .rectangle: return 150
        case .diamond:   return 140
        }
    }

    var defaultHeight: CGFloat {
        switch self {
        case .circle:    return 130
        case .oval:      return 95
        case .rectangle: return 90
        case .diamond:   return 110
        }
    }

    var shapeKind: String {
        switch self {
        case .circle:    return "CIRCLE"
        case .oval:      return "OVAL"
        case .rectangle: return "RECTANGLE"
        case .diamond:   return "DIAMOND"
        }
    }

    static func fromShapeKind(_ kind: String) -> BubbleShape {
        switch kind.uppercased() {
        case "CIRCLE":    return .circle
        case "OVAL":      return .oval
        case "RECTANGLE": return .rectangle
        case "DIAMOND":   return .diamond
        default:          return .circle
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
}

struct MindMapEdge: Identifiable {
    let id: UUID
    let fromId: UUID
    let toId: UUID
    var label: String

    init(id: UUID = UUID(), fromId: UUID, toId: UUID, label: String = "") {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.label = label
    }
}

// MARK: - MindMap ViewModel

@MainActor
final class MindMapDesignerViewModel: ObservableObject {
    @Published var nodes: [MindMapNode] = []
    @Published var edges: [MindMapEdge] = []
    @Published var selectedId: UUID? = nil
    @Published var connectMode: Bool = false
    @Published var connectFromId: UUID? = nil

    private var undoStack: [([MindMapNode], [MindMapEdge])] = []
    private var redoStack: [([MindMapNode], [MindMapEdge])] = []

    private var store: DiagramDocumentStore? = nil
    private var diagramId: String = UUID().uuidString
    @Published var diagramName: String = "MindMap"
    private var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init() {
        setupLiveCollabHooks()
    }

    func configure(folderURL: URL) {
        let store = DiagramDocumentStore(folderURL: folderURL)
        self.store = store

        if let doc = store.load() {
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
                return MindMapEdge(id: id, fromId: fromId, toId: toId, label: dto.label)
            }
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
                fromPort: "BOTTOM"
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
            return MindMapEdge(id: id, fromId: fromId, toId: toId, label: dto.label)
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
            guard let self = self else { return (nil, nil) }
            let dto = self.exportDTO()
            let data = try? JSONEncoder().encode(dto)
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            return (json, nil)
        }

        collab.onApplySnapshot = { [weak self] docJson, _ in
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
        }
        let node = MindMapNode(shape: shape, label: defaultLabel, color: color, cx: anchor.x, cy: anchor.y)
        nodes.append(node)
        selectedId = node.id
    }

    func move(id: UUID, to p: CGPoint) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            nodes[i].cx = p.x
            nodes[i].cy = p.y
        }
    }

    func tap(id: UUID) {
        if connectMode {
            if let from = connectFromId, from != id {
                if !edges.contains(where: { ($0.fromId == from && $0.toId == id) || ($0.fromId == id && $0.toId == from) }) {
                    pushUndo()
                    edges.append(MindMapEdge(fromId: from, toId: id))
                }
                connectFromId = nil
            } else {
                connectFromId = id
            }
        } else {
            selectedId = selectedId == id ? nil : id
        }
    }

    func deleteSelected() {
        guard let id = selectedId else { return }
        pushUndo()
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.fromId == id || $0.toId == id }
        selectedId = nil
    }

    func setNodeLabel(id: UUID, label: String) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            pushUndo()
            nodes[i].label = label
        }
    }

    // MARK: Export

    func renderToImage(drawing: PKDrawing? = nil) -> UIImage? {
        guard !nodes.isEmpty else { return nil }
        let pad: CGFloat = 60
        let minX = (nodes.map { $0.cx - $0.shape.defaultWidth/2  }.min() ?? 0) - pad
        let minY = (nodes.map { $0.cy - $0.shape.defaultHeight/2 }.min() ?? 0) - pad
        let maxX = (nodes.map { $0.cx + $0.shape.defaultWidth/2  }.max() ?? 400) + pad
        let maxY = (nodes.map { $0.cy + $0.shape.defaultHeight/2 }.max() ?? 600) + pad
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

// MARK: - Branch Curve Path

struct MindMapBranchPath: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let control1 = CGPoint(x: start.x + dx * 0.5, y: start.y)
        let control2 = CGPoint(x: start.x + dx * 0.5, y: end.y)
        p.addCurve(to: end, control1: control1, control2: control2)
        return p
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
        let (s, e) = branchEndpoints(from: from, to: to)
        let os = CGPoint(x: s.x + offset.x, y: s.y + offset.y)
        let oe = CGPoint(x: e.x + offset.x, y: e.y + offset.y)
        return AnyView(
            MindMapBranchPath(start: os, end: oe)
                .stroke(from.color.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        )
    }

    func branchEndpoints(from: MindMapNode, to: MindMapNode) -> (CGPoint, CGPoint) {
        let dx = to.cx - from.cx
        let fw = from.shape.defaultWidth, fh = from.shape.defaultHeight
        let tw = to.shape.defaultWidth,   th = to.shape.defaultHeight
        let s = CGPoint(x: dx >= 0 ? from.cx + fw/2 : from.cx - fw/2, y: from.cy)
        let e = CGPoint(x: dx >= 0 ? to.cx - tw/2 : to.cx + tw/2, y: to.cy)
        return (s, e)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: node.shape.defaultWidth - 16, maxHeight: node.shape.defaultHeight - 16)
        }
    }

    @ViewBuilder
    var shapeBackground: some View {
        let fill = node.color.opacity(0.12)
        let stroke = isSelected ? Color.orange : node.color
        let lineWidth: CGFloat = isSelected ? 3.5 : 2.5

        switch node.shape {
        case .circle:
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(stroke, lineWidth: lineWidth))
        case .oval:
            Capsule()
                .fill(fill)
                .overlay(Capsule().stroke(stroke, lineWidth: lineWidth))
        case .rectangle:
            RoundedRectangle(cornerRadius: 14)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke, lineWidth: lineWidth))
        case .diamond:
            DiamondShape()
                .fill(fill)
                .overlay(DiamondShape().stroke(stroke, lineWidth: lineWidth))
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

    private let bubbleColors: [Color] = [.blue, .purple, .teal, .green, .orange, .pink, .red]

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left shapes & actions palette
                shapePalette
                    .frame(width: 95)
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
        }
        .onAppear {
            if let item = item {
                vm.configure(folderURL: item.path)
            }
        }
        .onDisappear {
            vm.save()
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
                        vm.addNode(shape, color: selectedBubbleColor, near: CGPoint(x: 240, y: CGFloat(vm.nodes.count) * 110 + 100))
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
                        .padding(.vertical, 8)
                        .background(selectedBubbleColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Divider().padding(.vertical, 4)

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

                Divider().padding(.vertical, 4)

                // Color picker for new nodes
                Text("Farbe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(bubbleColors, id: \.self) { col in
                        Circle()
                            .fill(col)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.3), lineWidth: selectedBubbleColor == col ? 2 : 0)
                            )
                            .onTapGesture { selectedBubbleColor = col }
                    }
                }
                .padding(.horizontal, 8)
            }
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
                    )
                }

                // Connect hint banner
                if vm.connectMode {
                    Text(vm.connectFromId == nil ? "Start-Knoten antippen" : "Ziel-Knoten für Ast antippen")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
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

    func edgeBranchView(_ edge: MindMapEdge) -> some View {
        guard let from = vm.nodes.first(where: { $0.id == edge.fromId }),
              let to   = vm.nodes.first(where: { $0.id == edge.toId })
        else { return AnyView(EmptyView()) }

        let dx = to.cx - from.cx
        let fw = from.shape.defaultWidth
        let tw = to.shape.defaultWidth
        let s = CGPoint(x: dx >= 0 ? from.cx + fw/2 : from.cx - fw/2, y: from.cy)
        let e = CGPoint(x: dx >= 0 ? to.cx - tw/2 : to.cx + tw/2, y: to.cy)

        return AnyView(
            MindMapBranchPath(start: s, end: e)
                .stroke(from.color.opacity(0.85), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
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
            .disabled(vm.selectedId == nil)

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
}
