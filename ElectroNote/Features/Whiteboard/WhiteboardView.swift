import SwiftUI
import PencilKit
import UIKit

// MARK: - Whiteboard ViewController

final class WhiteboardViewController: UIViewController {

    let canvasView = PKCanvasView()
    private var backgroundStyle: BackgroundStyle = .blank
    private var darkDrawingMode: Bool = false

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

    private func setupCanvas() {
        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = .white
        canvasView.drawingPolicy = .anyInput  // pencil + finger drawing
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.contentSize = CGSize(width: 3000, height: 3000)
        canvasView.isScrollEnabled = true
        view.addSubview(canvasView)

        // Default tool: Pen
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
    }

    func refreshBackground(style: BackgroundStyle, dark: Bool) {
        self.backgroundStyle = style
        self.darkDrawingMode = dark
        let bg = dark ? UIColor(white: 0.12, alpha: 1) : UIColor.white
        let line = dark ? UIColor(white: 0.30, alpha: 1) : UIColor.systemGray4
        let pattern = UIColor(patternImage: makePattern(style, bg: bg, line: line))
        canvasView.backgroundColor = pattern
        view.backgroundColor = bg
    }

    private func makePattern(_ style: BackgroundStyle, bg: UIColor, line: UIColor) -> UIImage {
        let sp: CGFloat = 28
        switch style {
        case .blank:
            return solidColor(bg)
        case .lined:
            let s = CGSize(width: 1, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setStroke()
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: sp - 0.5)); p.addLine(to: CGPoint(x: 1, y: sp - 0.5)); p.stroke()
            }
        case .grid:
            let s = CGSize(width: sp, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setStroke()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: sp - 0.5, y: 0)); p.addLine(to: CGPoint(x: sp - 0.5, y: sp))
                p.move(to: CGPoint(x: 0, y: sp - 0.5)); p.addLine(to: CGPoint(x: sp, y: sp - 0.5))
                p.stroke()
            }
        case .dotted:
            let s = CGSize(width: sp, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setFill()
                ctx.fill(CGRect(x: sp/2 - 1, y: sp/2 - 1, width: 2, height: 2))
            }
        case .cornell:
            let s = CGSize(width: sp, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setStroke()
                let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: sp - 0.5)); p.addLine(to: CGPoint(x: 1, y: sp - 0.5)); p.stroke()
            }
        }
    }

    private func solidColor(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    func clearCanvas() {
        let alert = UIAlertController(title: "Whiteboard löschen?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
            self?.canvasView.drawing = PKDrawing()
        })
        present(alert, animated: true)
    }

    func undo() {
        canvasView.undoManager?.undo()
    }

    func redo() {
        canvasView.undoManager?.redo()
    }

    func exportImage(withBackground: Bool = true) -> UIImage? {
        let drawing = canvasView.drawing
        let bounds = drawing.bounds

        let targetRect: CGRect
        if !bounds.isNull && bounds.width > 5 && bounds.height > 5 {
            let padding: CGFloat = 24
            targetRect = CGRect(
                x: max(0, bounds.minX - padding),
                y: max(0, bounds.minY - padding),
                width: bounds.width + padding * 2,
                height: bounds.height + padding * 2
            )
        } else {
            let sz = canvasView.bounds.size
            let w = sz.width > 50 ? sz.width : 600
            let h = sz.height > 50 ? sz.height : 400
            targetRect = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        }

        let renderSize = CGSize(width: max(targetRect.width, 100), height: max(targetRect.height, 100))
        let inkImage = drawing.image(from: targetRect, scale: 2.0)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2.0
        return UIGraphicsImageRenderer(size: renderSize, format: fmt).image { ctx in
            if withBackground || darkDrawingMode {
                let bg = darkDrawingMode ? UIColor(white: 0.12, alpha: 1) : UIColor.white
                let line = darkDrawingMode ? UIColor(white: 0.30, alpha: 1) : UIColor.systemGray4
                let pattern = makePattern(backgroundStyle, bg: bg, line: line)
                pattern.draw(in: CGRect(origin: .zero, size: renderSize))
            } else {
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: renderSize))
            }
            if inkImage.size.width > 0 && inkImage.size.height > 0 {
                inkImage.draw(in: CGRect(origin: .zero, size: renderSize))
            }
        }
    }
}

// MARK: - Whiteboard Representable

struct WhiteboardRepresentable: UIViewControllerRepresentable {
    @Binding var vcRef: WhiteboardViewController?
    let background: BackgroundStyle
    let darkDrawingMode: Bool
    let rulerActive: Bool

    func makeUIViewController(context: Context) -> WhiteboardViewController {
        let vc = WhiteboardViewController()
        DispatchQueue.main.async { vcRef = vc }
        return vc
    }

    func updateUIViewController(_ vc: WhiteboardViewController, context: Context) {
        vc.refreshBackground(style: background, dark: darkDrawingMode)
        if vc.canvasView.isRulerActive != rulerActive {
            vc.canvasView.isRulerActive = rulerActive
        }
    }
}

// MARK: - Whiteboard SwiftUI View

struct WhiteboardView: View {
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var activeTool: CanvasToolType = .pen
    @State private var selectedColor: Color = .black
    @State private var selectedWidth: CGFloat = 3.0
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var rulerActive: Bool = false
    @State private var background: BackgroundStyle = .blank
    @State private var darkDrawingMode: Bool = false

    @State private var vc: WhiteboardViewController?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Dedicated Pen & Tool top bar
                PenToolbarView(
                    activeTool: $activeTool,
                    selectedColor: $selectedColor,
                    selectedWidth: $selectedWidth,
                    eraserType: $eraserType,
                    rulerActive: $rulerActive,
                    darkDrawingMode: darkDrawingMode,
                    showRuler: true
                ) { newTool in
                    vc?.canvasView.tool = newTool
                }
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))

                Divider()

                WhiteboardRepresentable(
                    vcRef: $vc,
                    background: background,
                    darkDrawingMode: darkDrawingMode,
                    rulerActive: rulerActive
                )
            }
            .navigationTitle("Whiteboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Schließen") { dismiss() }

                    Button { vc?.clearCanvas() } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .accessibilityLabel("Löschen")

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
                    // Background style menu
                    Menu {
                        Section("Vorlage") {
                            ForEach(BackgroundStyle.allCases) { style in
                                Button {
                                    background = style
                                } label: {
                                    Label(style.rawValue, systemImage: style.symbolName)
                                }
                            }
                        }
                        Section("Modus") {
                            Toggle("Dunkles Board", isOn: $darkDrawingMode)
                        }
                    } label: {
                        Image(systemName: background.symbolName)
                    }
                    .accessibilityLabel("Hintergrund")

                    Button {
                        if let img = vc?.exportImage(withBackground: background != .blank || darkDrawingMode) {
                            onInsert(img)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                            Text("Als Bild einfügen")
                        }
                        .font(.system(size: 14, weight: .bold))
                    }
                }
            }
        }
    }
}
