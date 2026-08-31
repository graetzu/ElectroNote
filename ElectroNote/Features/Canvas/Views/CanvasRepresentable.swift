import SwiftUI
import PencilKit

struct CanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var pencilOnly: Bool
    let onDrawingChanged: (PKDrawing) -> Void
    let onCanvasReady: (PKCanvasView) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 3.0

        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            onCanvasReady(canvas)
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let policy: PKCanvasView.DrawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if canvas.drawingPolicy != policy {
            canvas.drawingPolicy = policy
        }
        // Only push drawing update if it came from outside (e.g. load)
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasRepresentable
        var toolPicker: PKToolPicker?
        private var isUpdating = false

        init(_ parent: CanvasRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdating else { return }
            isUpdating = true
            let newDrawing = canvasView.drawing
            parent.drawing = newDrawing
            parent.onDrawingChanged(newDrawing)
            isUpdating = false
        }
    }
}
