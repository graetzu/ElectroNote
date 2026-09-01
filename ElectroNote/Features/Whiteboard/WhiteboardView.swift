import SwiftUI
import PencilKit
import UIKit

// MARK: - Whiteboard ViewController

final class WhiteboardViewController: UIViewController {

    let canvasView = PKCanvasView()
    let toolPicker = PKToolPicker()
    var onInsert: ((UIImage) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupCanvas()
        setupToolPicker()
        setupToolbar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
    }

    private func setupCanvas() {
        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = .white
        canvasView.drawingPolicy = .anyInput  // finger + pencil in whiteboard
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        view.addSubview(canvasView)

        // Default to a thick black marker for whiteboard feel
        canvasView.tool = PKInkingTool(.marker, color: .black, width: 8)
    }

    private func setupToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
    }

    private func setupToolbar() {
        let clearBtn = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain, target: self, action: #selector(clearCanvas)
        )
        clearBtn.tintColor = .systemRed

        let undoBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain, target: self, action: #selector(undoAction)
        )
        let redoBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain, target: self, action: #selector(redoAction)
        )
        let insertBtn = UIBarButtonItem(
            title: "Als Bild einfügen", style: .done,
            target: self, action: #selector(insertImage)
        )
        let closeBtn = UIBarButtonItem(
            image: UIImage(systemName: "xmark"), style: .plain,
            target: self, action: #selector(closeSheet)
        )

        navigationItem.leftBarButtonItems  = [closeBtn, clearBtn]
        navigationItem.rightBarButtonItems = [insertBtn, redoBtn, undoBtn]
        title = "Whiteboard"
    }

    @objc private func clearCanvas() {
        let alert = UIAlertController(title: "Whiteboard löschen?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
            self?.canvasView.drawing = PKDrawing()
        })
        present(alert, animated: true)
    }

    @objc private func undoAction() {
        UIApplication.shared.sendAction(#selector(UndoManager.undo), to: nil, from: nil, for: nil)
    }
    @objc private func redoAction() {
        UIApplication.shared.sendAction(#selector(UndoManager.redo), to: nil, from: nil, for: nil)
    }

    @objc private func insertImage() {
        let bounds = canvasView.drawing.bounds
        let renderRect = bounds.isNull ? CGRect(origin: .zero, size: view.bounds.size)
                                       : bounds.insetBy(dx: -30, dy: -30)
        let image = canvasView.drawing.image(from: renderRect, scale: 2)

        // Compose on white background
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let final = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        onInsert?(final)
        dismiss(animated: true)
    }

    @objc private func closeSheet() {
        dismiss(animated: true)
    }
}

// MARK: - SwiftUI wrapper

struct WhiteboardView: UIViewControllerRepresentable {
    let onInsert: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = WhiteboardViewController()
        vc.onInsert = onInsert
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
