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

    func path(in rect: CGRect) -> UIBezierPath {
        switch self {
        case .circle:
            let dim = min(rect.width, rect.height)
            let circleRect = CGRect(x: rect.midX - dim/2, y: rect.midY - dim/2, width: dim, height: dim)
            return UIBezierPath(ovalIn: circleRect)
        case .oval:
            return UIBezierPath(ovalIn: rect)
        case .rectangle:
            return UIBezierPath(roundedRect: rect, cornerRadius: 10)
        case .diamond:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.close()
            return p
        }
    }
}

// MARK: - MindMapBubble View

final class MindMapBubble: UIView {
    let shape: BubbleShape
    var color: UIColor = .systemBlue {
        didSet { updateShape() }
    }
    var onDelete: (() -> Void)?

    var isSelectedBubble: Bool = false {
        didSet { updateSelection() }
    }

    private let shapeLayer = CAShapeLayer()
    private let deleteButton = UIButton(type: .custom)

    init(shape: BubbleShape, frame: CGRect, color: UIColor = .systemBlue) {
        self.shape = shape
        self.color = color
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false

        shapeLayer.fillColor   = color.withAlphaComponent(0.06).cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth   = 2.5
        layer.addSublayer(shapeLayer)

        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteSelf), for: .touchUpInside)
        deleteButton.isHidden = true
        addSubview(deleteButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(tap)

        updateShape()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShape()
        deleteButton.frame = CGRect(x: bounds.width - 24, y: -8, width: 28, height: 28)
    }

    private func updateShape() {
        let path = shape.path(in: bounds.insetBy(dx: 4, dy: 4))
        shapeLayer.path = path.cgPath
        shapeLayer.frame = bounds
        shapeLayer.fillColor = color.withAlphaComponent(0.06).cgColor
        shapeLayer.strokeColor = isSelectedBubble ? UIColor.systemOrange.cgColor : color.cgColor
    }

    private func updateSelection() {
        shapeLayer.strokeColor = isSelectedBubble ? UIColor.systemOrange.cgColor : color.cgColor
        shapeLayer.lineWidth   = isSelectedBubble ? 3.5 : 2.5
        deleteButton.isHidden  = !isSelectedBubble
    }

    @objc private func handleTap() {
        isSelectedBubble.toggle()
    }

    @objc private func deleteSelf() {
        onDelete?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Let Apple Pencil touches pass directly through to PKCanvasView
        if let touches = event?.allTouches {
            for touch in touches {
                if touch.type == .pencil { return nil }
            }
        }
        // If delete button was tapped, handle it
        if !deleteButton.isHidden {
            let deletePoint = convert(point, to: deleteButton)
            if deleteButton.point(inside: deletePoint, with: event) {
                return deleteButton
            }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - MindMap ViewController

final class MindMapViewController: UIViewController {
    let canvasView = PKCanvasView()
    let toolPicker = PKToolPicker()
    var bubbles: [MindMapBubble] = []
    var onInsert: ((UIImage) -> Void)?
    var selectedBubble: MindMapBubble? {
        didSet {
            oldValue?.isSelectedBubble = false
            selectedBubble?.isSelectedBubble = true
        }
    }

    private func setupCanvas() {
        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.drawingPolicy = .anyInput   // pencil and finger can draw
        canvasView.backgroundColor = .white
        canvasView.contentSize = CGSize(width: 3000, height: 3000)
        canvasView.isScrollEnabled = true
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        view.addSubview(canvasView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupCanvas()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if canvasView.frame != view.bounds {
            canvasView.frame = view.bounds
        }
        if canvasView.contentSize.width < view.bounds.width {
            canvasView.contentSize = CGSize(width: max(view.bounds.width * 2, 2000), height: max(view.bounds.height * 2, 2000))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
    }

    func addBubble(shape: BubbleShape, color: UIColor = .systemBlue) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let size: CGSize
        switch shape {
        case .circle:    size = CGSize(width: 140, height: 140)
        case .oval:      size = CGSize(width: 180, height: 110)
        case .rectangle: size = CGSize(width: 170, height: 100)
        case .diamond:   size = CGSize(width: 150, height: 110)
        }

        let frame = CGRect(origin: CGPoint(x: center.x - size.width/2, y: center.y - size.height/2), size: size)
        let bubble = MindMapBubble(shape: shape, frame: frame, color: color)
        bubble.onDelete = { [weak self, weak bubble] in
            guard let self, let bubble else { return }
            bubble.removeFromSuperview()
            self.bubbles.removeAll { $0 === bubble }
            if self.selectedBubble === bubble { self.selectedBubble = nil }
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBubblePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        bubble.addGestureRecognizer(pan)

        view.addSubview(bubble)
        bubbles.append(bubble)
        selectedBubble = bubble
    }

    @objc private func handleBubblePan(_ pan: UIPanGestureRecognizer) {
        guard let bubble = pan.view as? MindMapBubble else { return }
        let delta = pan.translation(in: view)
        bubble.center = CGPoint(x: bubble.center.x + delta.x, y: bubble.center.y + delta.y)
        pan.setTranslation(.zero, in: view)
        selectedBubble = bubble
    }

    @objc private func deselectAll() {
        selectedBubble = nil
    }

    func undo() {
        canvasView.undoManager?.undo()
    }

    func redo() {
        canvasView.undoManager?.redo()
    }

    func exportAsImage() -> UIImage {
        let renderBounds = view.bounds
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        return UIGraphicsImageRenderer(bounds: renderBounds, format: fmt).image { _ in
            view.drawHierarchy(in: renderBounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - MindMap Representable

struct MindMapRepresentable: UIViewControllerRepresentable {
    @Binding var vcRef: MindMapViewController?

    func makeUIViewController(context: Context) -> MindMapViewController {
        let controller = MindMapViewController()
        DispatchQueue.main.async { vcRef = controller }
        return controller
    }

    func updateUIViewController(_ uiViewController: MindMapViewController, context: Context) {}
}

// MARK: - MindMap Designer SwiftUI View

struct MindMapDesignerView: View {
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var vc: MindMapViewController?

    @State private var activeTool: CanvasToolType = .pen
    @State private var selectedPenColor: Color = .black
    @State private var selectedWidth: CGFloat = 3.0
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var rulerActive: Bool = false

    @State private var selectedBubbleColor: Color = .blue
    private let bubbleColors: [Color] = [.blue, .green, .orange, .purple, .red, .teal]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                MindMapRepresentable(vcRef: $vc)
                    .ignoresSafeArea()

                // Dedicated Pen Toolbar for note-taking in MindMaps
                PenToolbarView(
                    activeTool: $activeTool,
                    selectedColor: $selectedPenColor,
                    selectedWidth: $selectedWidth,
                    eraserType: $eraserType,
                    rulerActive: $rulerActive,
                    darkDrawingMode: false,
                    showRuler: true
                ) { newTool in
                    vc?.canvasView.tool = newTool
                }
                .padding(.top, 8)
            }
            .navigationTitle("MindMap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }

                    Button { vc?.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Rückgängig")

                    Button { vc?.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .accessibilityLabel("Wiederholen")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Shapes menu
                    Menu {
                        Section("Form hinzufügen") {
                            ForEach(BubbleShape.allCases) { shape in
                                Button {
                                    vc?.addBubble(shape: shape, color: UIColor(selectedBubbleColor))
                                } label: {
                                    Label(shape.rawValue, systemImage: shape.symbolName)
                                }
                            }
                        }
                        Section("Formfarbe") {
                            ForEach(bubbleColors, id: \.self) { col in
                                Button {
                                    selectedBubbleColor = col
                                } label: {
                                    HStack {
                                        Text(col.description.capitalized)
                                        if selectedBubbleColor == col {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Form", systemImage: "plus.circle")
                    }

                    Button("Einfügen") {
                        if let img = vc?.exportAsImage() {
                            onInsert(img)
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
        }
    }
}
