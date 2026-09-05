import UIKit
import PDFKit
import PencilKit

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

    // MARK: - Page changes

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
}

// MARK: - PDFPageOverlayViewProvider

extension PDFAnnotationViewController: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let existing = canvasMap[page] {
            return existing
        }
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        canvas.drawingPolicy   = pencilOnly ? .pencilOnly : .anyInput
        canvas.delegate        = self

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
