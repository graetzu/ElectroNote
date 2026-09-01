import UIKit
import PDFKit
import PencilKit

// Manages PDFView + PKCanvasView overlay in a single UIViewController.
// Canvas is always positioned over the current PDF page; annotations are
// stored per page as sidecar .pkdrawing files.
final class PDFAnnotationViewController: UIViewController {

    // MARK: - Views
    private let pdfView    = PDFView()
    private var canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()

    // MARK: - State
    private var store: PDFAnnotationStore?
    private(set) var currentPageIndex: Int = 0
    private var saveTask: Task<Void, Never>?

    // MARK: - Callbacks (bridge to SwiftUI)
    var onPageChanged: ((Int) -> Void)?
    var onAnnotationChanged: (() -> Void)?

    // MARK: - Configuration

    func configure(document: PDFDocument, store: PDFAnnotationStore, pageIndex: Int = 0) {
        self.store = store

        pdfView.document        = document
        pdfView.displayMode     = .singlePage
        pdfView.autoScales      = true
        pdfView.backgroundColor = .systemGroupedBackground

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
        saveCurrentAnnotation()
        pdfView.go(to: page)
        // PDFViewPageChanged fires → handlePageChange loads annotation + updates frame
    }

    func saveAnnotations() { saveCurrentAnnotation() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupPDFView()
        setupCanvasView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadAnnotation(for: currentPageIndex)
        canvasView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCurrentAnnotation()
        saveTask?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pdfView.frame = view.bounds
        updateCanvasFrame()
    }

    // MARK: - Setup

    private func setupPDFView() {
        view.addSubview(pdfView)
        pdfView.frame = view.bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func setupCanvasView() {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque        = false
        canvasView.drawingPolicy   = .anyInput
        canvasView.delegate        = self

        view.addSubview(canvasView)

        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
    }

    // MARK: - Canvas positioning

    private func updateCanvasFrame() {
        guard let page = pdfView.currentPage else { return }
        let pageRect = pdfView.convert(page.bounds(for: .cropBox), from: page)
        canvasView.frame = view.convert(pageRect, from: pdfView)
    }

    // MARK: - Page changes

    @objc private func handlePageChange() {
        saveCurrentAnnotation()
        guard let page = pdfView.currentPage,
              let doc  = pdfView.document else { return }
        let idx = doc.index(for: page)
        guard idx != NSNotFound else { return }
        currentPageIndex = idx
        loadAnnotation(for: idx)
        updateCanvasFrame()
        onPageChanged?(idx)
    }

    @objc private func handleScaleChange() {
        updateCanvasFrame()
    }

    // MARK: - Annotation I/O

    private func loadAnnotation(for pageIndex: Int) {
        guard let store else { return }
        canvasView.drawing = store.loadDrawing(for: pageIndex)
    }

    private func saveCurrentAnnotation() {
        guard let store else { return }
        store.saveDrawing(canvasView.drawing, for: currentPageIndex)
        saveTask?.cancel()
    }
}

// MARK: - PKCanvasViewDelegate

extension PDFAnnotationViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onAnnotationChanged?()
        let drawing   = canvasView.drawing
        let pageIndex = currentPageIndex
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.store?.saveDrawing(drawing, for: pageIndex)
        }
    }
}
