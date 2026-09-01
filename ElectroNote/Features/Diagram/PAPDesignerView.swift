import SwiftUI

// MARK: - Shape types

enum PAPShapeType: String, CaseIterable, Identifiable {
    case start, end, process, io, decision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:    return "Start"
        case .end:      return "Ende"
        case .process:  return "Prozess"
        case .io:       return "Ein-/Ausgabe"
        case .decision: return "Entscheidung"
        }
    }

    var fillColor: Color {
        switch self {
        case .start, .end: return Color(red: 0.68, green: 0.85, blue: 1.0)
        case .process:     return Color(red: 0.65, green: 0.93, blue: 0.65)
        case .io:          return Color(red: 0.98, green: 0.62, blue: 0.62)
        case .decision:    return Color(red: 1.00, green: 0.82, blue: 0.30)
        }
    }

    var icon: String {
        switch self {
        case .start, .end: return "oval"
        case .process:     return "rectangle"
        case .io:          return "parallelogram"
        case .decision:    return "diamond"
        }
    }

    var defaultWidth:  CGFloat { self == .decision ? 140 : 160 }
    var defaultHeight: CGFloat { self == .decision ?  80 :  58 }
}

// MARK: - Models

struct PAPNode: Identifiable {
    var id    = UUID()
    var type:  PAPShapeType
    var label: String
    var cx: CGFloat   // center x
    var cy: CGFloat   // center y
    var tag: String = ""   // "A" / "E" badge on IO nodes
}

struct PAPEdge: Identifiable {
    var id     = UUID()
    var fromId: UUID
    var toId:   UUID
    var label:  String = ""
}

// MARK: - Custom Shapes

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
    var slant: CGFloat = 18
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

// MARK: - ViewModel

@MainActor
final class PAPDesignerViewModel: ObservableObject {
    @Published var nodes: [PAPNode] = [
        PAPNode(type: .start, label: "Start", cx: 200, cy: 60)
    ]
    @Published var edges: [PAPEdge] = []
    @Published var selectedId: UUID? = nil
    @Published var connectMode = false
    @Published var connectFromId: UUID? = nil
    @Published var editingNode: PAPNode? = nil

    func addNode(_ type: PAPShapeType, near anchor: CGPoint) {
        let label: String
        switch type {
        case .start:    label = "Start"
        case .end:      label = "Ende"
        case .process:  label = "Prozess"
        case .io:       label = "Eingabe"
        case .decision: label = "Bedingung?"
        }
        nodes.append(PAPNode(type: type, label: label, cx: anchor.x, cy: anchor.y))
    }

    func move(id: UUID, to p: CGPoint) {
        if let i = nodes.firstIndex(where: { $0.id == id }) { nodes[i].cx = p.x; nodes[i].cy = p.y }
    }

    func tap(id: UUID) {
        if connectMode {
            if let from = connectFromId, from != id {
                if !edges.contains(where: { $0.fromId == from && $0.toId == id }) {
                    edges.append(PAPEdge(fromId: from, toId: id))
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
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.fromId == id || $0.toId == id }
        selectedId = nil
    }

    func setEdgeLabel(_ edge: PAPEdge, label: String) {
        if let i = edges.firstIndex(where: { $0.id == edge.id }) { edges[i].label = label }
    }

    // MARK: Export

    func renderToImage() -> UIImage? {
        guard !nodes.isEmpty else { return nil }
        let pad: CGFloat = 50
        let minX = (nodes.map { $0.cx - $0.type.defaultWidth/2  }.min() ?? 0) - pad
        let minY = (nodes.map { $0.cy - $0.type.defaultHeight/2 }.min() ?? 0) - pad
        let maxX = (nodes.map { $0.cx + $0.type.defaultWidth/2  }.max() ?? 400) + pad
        let maxY = (nodes.map { $0.cy + $0.type.defaultHeight/2 }.max() ?? 600) + pad
        let w = max(maxX - minX, 200)
        let h = max(maxY - minY, 200)
        let offset = CGPoint(x: -minX, y: -minY)
        let view = PAPRenderView(nodes: nodes, edges: edges, offset: offset)
            .frame(width: w, height: h)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

// MARK: - Pure render view (for export)

struct PAPRenderView: View {
    let nodes: [PAPNode]
    let edges: [PAPEdge]
    let offset: CGPoint

    var body: some View {
        ZStack {
            ForEach(edges) { edge in
                edgeArrow(edge)
            }
            ForEach(nodes) { node in
                PAPNodeView(node: node, isSelected: false)
                    .position(x: node.cx + offset.x, y: node.cy + offset.y)
            }
        }
    }

    func edgeArrow(_ edge: PAPEdge) -> some View {
        guard let from = nodes.first(where: { $0.id == edge.fromId }),
              let to   = nodes.first(where: { $0.id == edge.toId }) else {
            return AnyView(EmptyView())
        }
        let (s, e) = endpoints(from: from, to: to)
        let os = CGPoint(x: s.x + offset.x, y: s.y + offset.y)
        let oe = CGPoint(x: e.x + offset.x, y: e.y + offset.y)
        return AnyView(
            ZStack {
                ArrowPath(start: os, end: oe)
                    .stroke(Color(white: 0.2), lineWidth: 1.5)
                if !edge.label.isEmpty {
                    Text(edge.label)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .position(x: (os.x + oe.x)/2 + 12, y: (os.y + oe.y)/2 - 10)
                }
            }
        )
    }

    func endpoints(from: PAPNode, to: PAPNode) -> (CGPoint, CGPoint) {
        let fw = from.type.defaultWidth, fh = from.type.defaultHeight
        let tw = to.type.defaultWidth,   th = to.type.defaultHeight
        let dx = to.cx - from.cx, dy = to.cy - from.cy
        if abs(dy) >= abs(dx) {
            let sy = dy > 0 ? from.cy + fh/2 : from.cy - fh/2
            let ey = dy > 0 ? to.cy   - th/2 : to.cy   + th/2
            return (CGPoint(x: from.cx, y: sy), CGPoint(x: to.cx, y: ey))
        } else {
            let sx = dx > 0 ? from.cx + fw/2 : from.cx - fw/2
            let ex = dx > 0 ? to.cx   - tw/2 : to.cx   + tw/2
            return (CGPoint(x: sx, y: from.cy), CGPoint(x: ex, y: to.cy))
        }
    }
}

// MARK: - Arrow path shape

struct ArrowPath: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: start); p.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let al: CGFloat = 12, aa: CGFloat = .pi / 6
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - al*cos(angle-aa), y: end.y - al*sin(angle-aa)))
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - al*cos(angle+aa), y: end.y - al*sin(angle+aa)))
        return p
    }
}

// MARK: - Node view

struct PAPNodeView: View {
    let node: PAPNode
    let isSelected: Bool

    var body: some View {
        ZStack {
            nodeShape
                .fill(node.type.fillColor)
            nodeShape
                .stroke(isSelected ? Color.blue : Color(white: 0.25), lineWidth: isSelected ? 2.5 : 1.5)
            if node.type == .io && !node.tag.isEmpty {
                Text(node.tag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }
            Text(node.label)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(white: 0.12))
                .padding(.horizontal, node.type == .io ? 22 : 10)
                .padding(.vertical, 4)
        }
        .frame(width: node.type.defaultWidth, height: node.type.defaultHeight)
        .shadow(color: .black.opacity(0.12), radius: 3, x: 1, y: 2)
    }

    var nodeShape: AnyShape {
        switch node.type {
        case .start, .end: return AnyShape(Capsule())
        case .process:     return AnyShape(RoundedRectangle(cornerRadius: 5))
        case .io:          return AnyShape(ParallelogramShape())
        case .decision:    return AnyShape(DiamondShape())
        }
    }
}

// AnyShape wrapper for type erasure
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { _path = shape.path(in:) }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

// MARK: - Main designer view

struct PAPDesignerView: View {
    @StateObject private var vm = PAPDesignerViewModel()
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var canvasOffset = CGPoint(x: 60, y: 30)
    @State private var scale: CGFloat = 1.0
    @State private var editLabelText = ""
    @State private var showEditLabel = false
    @State private var editingEdge: PAPEdge? = nil

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left palette
                shapePalette
                    .frame(width: 90)
                    .background(Color(.systemGroupedBackground))

                Divider()

                // Canvas
                canvas
            }
            .navigationTitle("PAP-Designer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Label bearbeiten", isPresented: $showEditLabel) {
                TextField("Text", text: $editLabelText)
                Button("OK") { applyLabelEdit() }
                Button("Abbrechen", role: .cancel) {}
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
                ForEach(PAPShapeType.allCases) { type in
                    Button {
                        vm.addNode(type, near: CGPoint(x: 200, y: CGFloat(vm.nodes.count) * 100 + 60))
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.title3)
                                .foregroundStyle(.primary)
                            Text(type.title)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(type.fillColor.opacity(0.4))
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
                        Image(systemName: vm.connectMode ? "arrow.triangle.turn.up.right.circle.fill" : "arrow.triangle.turn.up.right.circle")
                            .font(.title3)
                            .foregroundStyle(vm.connectMode ? .blue : .primary)
                        Text(vm.connectMode ? "Verbinden\naktiv" : "Verbinden")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(vm.connectMode ? Color.blue.opacity(0.15) : Color(.systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: Canvas

    var canvas: some View {
        ZStack(alignment: .topLeading) {
            // Grid background
            Canvas { ctx, size in
                let step: CGFloat = 30
                var path = Path()
                var x: CGFloat = 0
                while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(path, with: .color(Color(white: 0.88)), lineWidth: 0.5)
            }
            .background(Color(white: 0.97))
            .contentShape(Rectangle())
            .onTapGesture { vm.selectedId = nil; vm.connectFromId = nil }

            // Edges
            ForEach(vm.edges) { edge in
                edgeView(edge)
            }

            // Nodes
            ForEach(vm.nodes) { node in
                PAPNodeView(node: node, isSelected: vm.selectedId == node.id ||
                            vm.connectFromId == node.id)
                    .position(x: node.cx, y: node.cy)
                    .onTapGesture { vm.tap(id: node.id) }
                    .onLongPressGesture {
                        vm.selectedId = node.id
                        editLabelText = node.label
                        editingEdge = nil
                        showEditLabel = true
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                if !vm.connectMode { vm.move(id: node.id, to: v.location) }
                            }
                    )
            }

            // Connect hint
            if vm.connectMode {
                Text(vm.connectFromId == nil ? "Quelle antippen" : "Ziel antippen")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .clipped()
    }

    func edgeView(_ edge: PAPEdge) -> some View {
        guard let from = vm.nodes.first(where: { $0.id == edge.fromId }),
              let to   = vm.nodes.first(where: { $0.id == edge.toId })
        else { return AnyView(EmptyView()) }

        let dx = to.cx - from.cx, dy = to.cy - from.cy
        let fw = from.type.defaultWidth, fh = from.type.defaultHeight
        let tw = to.type.defaultWidth,   th = to.type.defaultHeight
        let s: CGPoint, e: CGPoint
        if abs(dy) >= abs(dx) {
            s = CGPoint(x: from.cx, y: dy > 0 ? from.cy + fh/2 : from.cy - fh/2)
            e = CGPoint(x: to.cx,   y: dy > 0 ? to.cy   - th/2 : to.cy   + th/2)
        } else {
            s = CGPoint(x: dx > 0 ? from.cx + fw/2 : from.cx - fw/2, y: from.cy)
            e = CGPoint(x: dx > 0 ? to.cx   - tw/2 : to.cx   + tw/2, y: to.cy)
        }

        return AnyView(
            ZStack {
                ArrowPath(start: s, end: e)
                    .stroke(Color(white: 0.2), lineWidth: 1.5)
                if !edge.label.isEmpty {
                    Text(edge.label)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .position(x: (s.x + e.x)/2 + 14, y: (s.y + e.y)/2 - 10)
                }
                // Invisible tap area on midpoint for label editing
                Color.clear
                    .frame(width: 60, height: 30)
                    .contentShape(Rectangle())
                    .position(x: (s.x + e.x)/2, y: (s.y + e.y)/2)
                    .onTapGesture {
                        editingEdge = edge
                        editLabelText = edge.label
                        showEditLabel = true
                    }
            }
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(role: .destructive) { vm.deleteSelected() } label: {
                Image(systemName: "trash")
            }
            .disabled(vm.selectedId == nil)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Einfügen") {
                if let img = vm.renderToImage() { onInsert(img); dismiss() }
            }
            .bold()
            .disabled(vm.nodes.isEmpty)
        }
    }

    func applyLabelEdit() {
        if let edge = editingEdge {
            vm.setEdgeLabel(edge, label: editLabelText)
            editingEdge = nil
        } else if let id = vm.selectedId,
                  let i = vm.nodes.firstIndex(where: { $0.id == id }) {
            vm.nodes[i].label = editLabelText
        }
    }
}
