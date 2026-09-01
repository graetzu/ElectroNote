import SwiftUI

// MARK: - Model

final class MindMapNode: Identifiable, ObservableObject {
    let id = UUID()
    @Published var text: String
    @Published var children: [MindMapNode] = []
    var color: Color
    var level: Int

    init(text: String, color: Color = .blue, level: Int = 0) {
        self.text = text; self.color = color; self.level = level
    }

    func addChild(text: String, palette: [Color]) -> MindMapNode {
        let c = MindMapNode(text: text,
                            color: palette[children.count % palette.count],
                            level: level + 1)
        children.append(c)
        return c
    }

    func remove(child id: UUID) {
        children.removeAll { $0.id == id }
    }
}

// MARK: - ViewModel

@MainActor
final class MindMapViewModel: ObservableObject {
    @Published var root = MindMapNode(text: "Hauptthema", color: .blue, level: 0)
    @Published var selectedId: UUID? = nil
    @Published var layoutVersion = 0   // triggers re-layout

    let palette: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .teal]

    // Computed radial layout positions
    private var positions: [UUID: CGPoint] = [:]
    private let center   = CGPoint(x: 320, y: 320)
    private let radii    = [CGFloat(140), CGFloat(260), CGFloat(370)]

    func layout() {
        positions.removeAll()
        positions[root.id] = center
        layoutChildren(of: root, parentAngle: nil, angleRange: 2 * .pi)
    }

    private func layoutChildren(of node: MindMapNode, parentAngle: CGFloat?, angleRange: CGFloat) {
        let n = node.children.count
        guard n > 0 else { return }
        let radius = radii[min(node.level, radii.count - 1)]
        let startAngle = (parentAngle ?? 0) - angleRange / 2
        let step = angleRange / CGFloat(n)
        for (i, child) in node.children.enumerated() {
            let angle = startAngle + step * (CGFloat(i) + 0.5)
            let parentPos = positions[node.id] ?? center
            positions[child.id] = CGPoint(
                x: parentPos.x + radius * cos(angle),
                y: parentPos.y + radius * sin(angle)
            )
            layoutChildren(of: child, parentAngle: angle, angleRange: max(step * 0.8, .pi / 3))
        }
    }

    func position(of id: UUID) -> CGPoint { positions[id] ?? center }

    func addChild(to parentId: UUID) {
        addChildRecursive(to: root, parentId: parentId)
        layoutVersion += 1
    }

    private func addChildRecursive(to node: MindMapNode, parentId: UUID) {
        if node.id == parentId { _ = node.addChild(text: "Thema", palette: palette); return }
        node.children.forEach { addChildRecursive(to: $0, parentId: parentId) }
    }

    func delete(id: UUID) {
        deleteRecursive(from: root, id: id)
        if selectedId == id { selectedId = nil }
        layoutVersion += 1
    }

    private func deleteRecursive(from node: MindMapNode, id: UUID) {
        node.remove(child: id)
        node.children.forEach { deleteRecursive(from: $0, id: id) }
    }

    func rename(id: UUID, text: String) {
        renameRecursive(in: root, id: id, text: text)
    }

    private func renameRecursive(in node: MindMapNode, id: UUID, text: String) {
        if node.id == id { node.text = text; return }
        node.children.forEach { renameRecursive(in: $0, id: id, text: text) }
    }

    func renderToImage() -> UIImage? {
        layout()
        let pad: CGFloat = 60
        let allPos = positions.values
        let minX = (allPos.map(\.x).min() ?? 0) - pad
        let minY = (allPos.map(\.y).min() ?? 0) - pad
        let maxX = (allPos.map(\.x).max() ?? 0) + pad
        let maxY = (allPos.map(\.y).max() ?? 0) + pad
        let w = max(maxX - minX, 300), h = max(maxY - minY, 300)
        let view = MindMapRenderView(vm: self, offset: CGPoint(x: -minX, y: -minY))
            .frame(width: w, height: h)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

// MARK: - Render view (export)

struct MindMapRenderView: View {
    let vm: MindMapViewModel
    let offset: CGPoint

    var body: some View {
        ZStack {
            connections(node: vm.root)
            bubbles(node: vm.root)
        }
    }

    func pos(_ id: UUID) -> CGPoint {
        let p = vm.position(of: id)
        return CGPoint(x: p.x + offset.x, y: p.y + offset.y)
    }

    func connections(node: MindMapNode) -> AnyView {
        AnyView(Group {
            ForEach(node.children) { child in
                let p = pos(node.id), c = pos(child.id)
                Path { path in
                    path.move(to: p); path.addLine(to: c)
                }
                .stroke(child.color.opacity(0.6), lineWidth: node.level == 0 ? 2.5 : 1.5)
            }
            ForEach(node.children) { child in
                connections(node: child)
            }
        })
    }

    func bubbles(node: MindMapNode) -> AnyView {
        AnyView(Group {
            nodeBubble(node)
            ForEach(node.children) { child in
                bubbles(node: child)
            }
        })
    }

    func nodeBubble(_ node: MindMapNode) -> some View {
        let p = pos(node.id)
        let isRoot = node.level == 0
        return Text(node.text)
            .font(.system(size: isRoot ? 15 : 13, weight: isRoot ? .bold : .regular))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, isRoot ? 16 : 10)
            .padding(.vertical, isRoot ? 10 : 6)
            .background(node.color)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 3)
            .position(p)
    }
}

// MARK: - Designer View

struct MindMapDesignerView: View {
    @StateObject private var vm = MindMapViewModel()
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editText = ""
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.97).ignoresSafeArea()
                mindMapCanvas
            }
            .navigationTitle("MindMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert("Knoten umbenennen", isPresented: $showEdit) {
                TextField("Text", text: $editText)
                Button("OK") {
                    if let id = vm.selectedId { vm.rename(id: id, text: editText) }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .onChange(of: vm.layoutVersion) { _ in vm.layout() }
            .onAppear { vm.layout() }
        }
    }

    var mindMapCanvas: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                // Connections
                Canvas { ctx, _ in
                    drawConnections(ctx: ctx, node: vm.root)
                }
                .frame(width: 640, height: 640)

                // Nodes
                allBubbles(node: vm.root)
            }
            .frame(width: 640, height: 640)
        }
    }

    func drawConnections(ctx: GraphicsContext, node: MindMapNode) {
        for child in node.children {
            let p = vm.position(of: node.id), c = vm.position(of: child.id)
            var path = Path()
            path.move(to: p); path.addLine(to: c)
            ctx.stroke(path, with: .color(child.color.opacity(0.5)),
                       style: StrokeStyle(lineWidth: node.level == 0 ? 2.5 : 1.5))
            drawConnections(ctx: ctx, node: child)
        }
    }

    func allBubbles(node: MindMapNode) -> AnyView {
        AnyView(Group {
            bubble(node)
            ForEach(node.children) { child in allBubbles(node: child) }
        })
    }

    func bubble(_ node: MindMapNode) -> some View {
        let isRoot = node.level == 0
        let isSelected = vm.selectedId == node.id
        return Text(node.text)
            .font(.system(size: isRoot ? 15 : 12, weight: isRoot ? .bold : .regular))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, isRoot ? 16 : 10)
            .padding(.vertical, isRoot ? 10 : 6)
            .background(node.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.white : Color.clear, lineWidth: 2.5)
                         .shadow(color: .blue, radius: isSelected ? 4 : 0))
            .shadow(color: .black.opacity(0.15), radius: 3)
            .position(vm.position(of: node.id))
            .onTapGesture { vm.selectedId = node.id }
            .onLongPressGesture {
                vm.selectedId = node.id
                let cur = findNode(root: vm.root, id: node.id)
                editText = cur?.text ?? ""
                showEdit = true
            }
    }

    func findNode(root: MindMapNode, id: UUID) -> MindMapNode? {
        if root.id == id { return root }
        for c in root.children { if let n = findNode(root: c, id: id) { return n } }
        return nil
    }

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { dismiss() }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Add child to selected / root
            Button {
                vm.addChild(to: vm.selectedId ?? vm.root.id)
            } label: { Image(systemName: "plus.bubble") }

            // Delete selected (not root)
            Button(role: .destructive) {
                if let id = vm.selectedId, id != vm.root.id { vm.delete(id: id) }
            } label: { Image(systemName: "trash") }
            .disabled(vm.selectedId == nil || vm.selectedId == vm.root.id)

            Button("Einfügen") {
                if let img = vm.renderToImage() { onInsert(img); dismiss() }
            }
            .bold()
        }
    }
}
