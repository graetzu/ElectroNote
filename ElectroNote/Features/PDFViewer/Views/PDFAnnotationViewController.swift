import UIKit
import PDFKit
import PencilKit

// MARK: - PDFOverlayCanvasView
// Custom PKCanvasView that transparently yields finger touches to the underlying PDFView
// so that native 1-finger scrolling and 2-finger pinch-to-zoom work smoothly, while
// Apple Pencil draws with zero latency.
final class PDFOverlayCanvasView: PKCanvasView {
    var pencilOnly: Bool = true

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }

        if let touches = event?.allTouches, !touches.isEmpty {
            let hasPencil = touches.contains { $0.type == .pencil }
            if hasPencil {
                return super.hitTest(point, with: event)
            }
            // All touches are finger touches:
            if pencilOnly {
                // Pass ALL finger touches (1-finger pan, 2-finger pinch-to-zoom) through to PDFView
                return nil
            } else {
                // In finger-drawing mode: 2 or more fingers pass through to PDFView for zoom & scroll
                if touches.count >= 2 {
                    return nil
                }
                return super.hitTest(point, with: event)
            }
        }

        // When event?.allTouches is nil/empty during initial hit testing, return super so PencilKit can receive Apple Pencil touches
        return super.hitTest(point, with: event)
    }
}

// Manages PDFView + PKCanvasView overlay using PDFPageOverlayViewProvider.
// Native pinch-to-zoom and panning are fully enabled; annotations are
// synchronized per page and stored as sidecar .pkdrawing files.
final class PDFAnnotationViewController: UIViewController {

    // MARK: - Views
    private let pdfView    = PDFView()
    private let toolPicker = PKToolPicker()

    // MARK: - State
    private var store: PDFAnnotationStore?
    private(set) var currentPageIndex: Int = 0
    private var canvasMap: [PDFPage: PKCanvasView] = [:]
    private var activeCanvasView: PKCanvasView?

    var pencilOnly: Bool = true {
        didSet {
            for canvas in canvasMap.values {
                canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
                if let overlay = canvas as? PDFOverlayCanvasView {
                    overlay.pencilOnly = pencilOnly
                }
            }
        }
    }

    // MARK: - Callbacks (bridge to SwiftUI)
    var onPageChanged: ((Int) -> Void)?
    var onAnnotationChanged: (() -> Void)?

    // MARK: - Configuration

    func configure(document: PDFDocument, store: PDFAnnotationStore, pageIndex: Int = 0) {
        self.store = store

        pdfView.document        = document
        pdfView.displayMode     = .singlePageContinuous
        pdfView.autoScales      = true
        pdfView.minScaleFactor  = 0.25
        pdfView.maxScaleFactor  = 5.0
        pdfView.backgroundColor = .systemGroupedBackground
        pdfView.pageOverlayViewProvider = self

        if let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        currentPageIndex = pageIndex

        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePageChange),
            name: .PDFViewPageChanged, object: pdfView)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScaleChange),
            name: .PDFViewScaleChanged, object: pdfView)
    }

    func navigateTo(pageIndex: Int) {
        guard let doc = pdfView.document,
              let page = doc.page(at: pageIndex) else { return }
        saveAnnotations()
        pdfView.go(to: page)
    }

    func saveAnnotations() {
        guard let store, let doc = pdfView.document else { return }
        for (page, canvas) in canvasMap {
            let idx = doc.index(for: page)
            if idx != NSNotFound {
                store.saveDrawing(canvas.drawing, for: idx)
            }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupPDFView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let current = pdfView.currentPage, let canvas = canvasMap[current] {
            activeCanvasView = canvas
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveAnnotations()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if pdfView.frame != view.bounds {
            pdfView.frame = view.bounds
        }
    }

    // MARK: - Setup

    private func setupPDFView() {
        view.addSubview(pdfView)
        pdfView.frame = view.bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    // MARK: - Page & Scale changes

    @objc private func handlePageChange() {
        guard let page = pdfView.currentPage,
              let doc  = pdfView.document else { return }
        let idx = doc.index(for: page)
        guard idx != NSNotFound else { return }
        currentPageIndex = idx
        if let canvas = canvasMap[page] {
            activeCanvasView = canvas
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        onPageChanged?(idx)
    }

    @objc private func handleScaleChange() {
        let scale = pdfView.scaleFactor
        for canvas in canvasMap.values {
            canvas.contentScaleFactor = UIScreen.main.scale * max(scale, 1.0)
        }
    }
}

// MARK: - PDFPageOverlayViewProvider

extension PDFAnnotationViewController: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let existing = canvasMap[page] {
            return existing
        }
        let canvas = PDFOverlayCanvasView()
        canvas.pencilOnly      = pencilOnly
        canvas.isScrollEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.panGestureRecognizer.isEnabled    = false
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.drawingPolicy   = pencilOnly ? .pencilOnly : .anyInput
        canvas.delegate        = self
        canvas.contentScaleFactor = UIScreen.main.scale * max(view.scaleFactor, 1.0)

        if let doc = view.document {
            let idx = doc.index(for: page)
            if idx != NSNotFound, let store = self.store {
                canvas.drawing = store.loadDrawing(for: idx)
            }
        }
        canvasMap[page] = canvas
        return canvas
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView else { return }
        activeCanvasView = canvas
        canvas.contentScaleFactor = UIScreen.main.scale * max(pdfView.scaleFactor, 1.0)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
    }

    func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView, let doc = view.document else { return }
        let idx = doc.index(for: page)
        if idx != NSNotFound {
            store?.saveDrawing(canvas.drawing, for: idx)
        }
    }
}

// MARK: - PKCanvasViewDelegate

extension PDFAnnotationViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onAnnotationChanged?()
        guard let doc = pdfView.document else { return }
        for (page, canvas) in canvasMap where canvas === canvasView {
            let idx = doc.index(for: page)
            if idx != NSNotFound {
                store?.saveDrawing(canvas.drawing, for: idx)
            }
            break
        }
    }
}
