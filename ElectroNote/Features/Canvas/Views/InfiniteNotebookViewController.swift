import UIKit
import PencilKit
import PDFKit
import Vision

// MARK: - Main

final class InfiniteNotebookViewController: UIViewController {

    // MARK: - Constants
    static let initialHeight: CGFloat = NotebookDocument.initialHeight

    // MARK: - Views
    var canvasView  = PKCanvasView()
    let toolPicker  = PKToolPicker()

    // MARK: - Content layers (below the PencilKit Metal layer)
    private var pdfLayers:   [CALayer] = []
    private var imageLayers: [CALayer] = []

    // MARK: - Math/handwriting result labels (above canvas, in scroll space)
    private var resultLabels: [UILabel] = []
    private var scanTask:     Task<Void, Never>?
    private let evaluator  =  MathEvaluator()

    // MARK: - State
    private(set) var document = NotebookDocument()
    var store: NotebookDocumentStore!
    private var didLoad = false

    // MARK: - Callbacks
    var onDrawingChanged: (() -> Void)?

    // MARK: - Configurable

    var pencilOnly: Bool = true {
        didSet { canvasView.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput }
    }

    var mathEnabled: Bool {
        get { document.mathEnabled }
        set { document.mathEnabled = newValue; if !newValue { clearResultLabels() } }
    }

    var background: BackgroundStyle {
        get { document.background }
        set { document.background = newValue; applyBackground(newValue); store?.saveDocument(document) }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupCanvas()
        setupToolPicker()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update canvas frame to fill view
        if canvasView.frame != view.bounds {
            canvasView.frame = view.bounds
        }
        if !didLoad {
            didLoad = true
            loadDocument()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        save()
    }

    // MARK: - Setup

    private func setupCanvas() {
        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Let PKCanvasView manage its own scrolling and zooming natively
        canvasView.minimumZoomScale = 0.25
        canvasView.maximumZoomScale = 8.0
        canvasView.drawingPolicy   = .pencilOnly
        canvasView.delegate        = self
        view.addSubview(canvasView)
    }

    private func setupToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
    }

    // MARK: - Load

    private func loadDocument() {
        guard store != nil else { return }
        document = store.loadDocument()
        applyBackground(document.background)
        canvasView.drawing = store.loadDrawing()

        // Extend content area if the stored height is larger than the loaded drawing
        let h = max(document.documentHeight,
                    canvasView.drawing.bounds.maxY + Self.initialHeight * 0.5)
        canvasView.contentSize = CGSize(width: view.bounds.width, height: h)

        document.insertedPDFs.forEach   { loadPDFEntry($0) }
        document.insertedImages.forEach { loadImageEntry($0) }
    }

    // MARK: - Background

    private func applyBackground(_ style: BackgroundStyle) {
        canvasView.backgroundColor = UIColor(patternImage: makePattern(style))
    }

    private func makePattern(_ style: BackgroundStyle) -> UIImage {
        switch style {
        case .blank:  return solidColor(.white)
        case .lined:  return linedImage()
        case .grid:   return gridImage()
        case .dotted: return dottedImage()
        }
    }

    private func solidColor(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func gridImage() -> UIImage {
        let s: CGFloat = 28
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            UIColor.systemGray4.setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: s, y: 0));  ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.move(to: CGPoint(x: 0, y: s));  ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.strokePath()
        }
    }

    private func linedImage() -> UIImage {
        let s: CGFloat = 32
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: s))
            UIColor.systemBlue.withAlphaComponent(0.2).setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: 0, y: s - 0.5))
            ctx.cgContext.addLine(to: CGPoint(x: 20, y: s - 0.5))
            ctx.cgContext.strokePath()
        }
    }

    private func dottedImage() -> UIImage {
        let s: CGFloat = 26
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            UIColor.systemGray3.setFill()
            ctx.cgContext.addEllipse(in: CGRect(x: s - 1.5, y: s - 1.5, width: 2.5, height: 2.5))
            ctx.cgContext.fillPath()
        }
    }

    // MARK: - Auto-extend

    private func extendIfNeeded() {
        let needed = canvasView.drawing.bounds.maxY + Self.initialHeight * 0.3
        guard needed > canvasView.contentSize.height else { return }
        let newH = needed + Self.initialHeight * 0.5
        canvasView.contentSize.height = newH
        document.documentHeight = newH
        store?.saveDocument(document)
    }

    // MARK: - Save

    func save() {
        store?.saveDrawing(canvasView.drawing)
        document.documentHeight = canvasView.contentSize.height
        store?.saveDocument(document)
    }
}

// MARK: - PDF & Image Insertion

extension InfiniteNotebookViewController {

    func insertPDF(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let filename = try? store.copyPDF(from: url),
              let pdf = PDFDocument(url: store.pdfURL(filename: filename))
        else { return }

        let startY = nextInsertY()
        var y = startY
        var heights: [CGFloat] = []

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let h = addPDFLayer(page: page, at: y)
            heights.append(h)
            y += h
        }

        let needed = y + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height {
            canvasView.contentSize.height = needed
        }

        let entry = InsertedPDF(id: UUID(), filename: filename, startY: startY, pageHeights: heights)
        document.insertedPDFs.append(entry)
        document.documentHeight = canvasView.contentSize.height
        store.saveDocument(document)

        canvasView.setContentOffset(CGPoint(x: 0, y: max(0, startY - 40)), animated: true)
    }

    func insertImage(_ image: UIImage) {
        guard let filename = try? store.saveImage(image) else { return }

        let startY  = nextInsertY()
        let w       = canvasView.contentSize.width
        let ratio   = image.size.height / image.size.width
        let h       = w * ratio

        let layer = makeImageLayer(image: image,
                                   frame: CGRect(x: 0, y: startY, width: w, height: h))
        insertBelowDrawing(layer)
        imageLayers.append(layer)

        let needed = startY + h + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height {
            canvasView.contentSize.height = needed
        }

        let entry = InsertedImage(id: UUID(), filename: filename,
                                  startY: startY, width: w, height: h)
        document.insertedImages.append(entry)
        document.documentHeight = canvasView.contentSize.height
        store.saveDocument(document)

        canvasView.setContentOffset(CGPoint(x: 0, y: max(0, startY - 40)), animated: true)
    }

    // MARK: - Load on open

    private func loadPDFEntry(_ entry: InsertedPDF) {
        guard let pdf = PDFDocument(url: store.pdfURL(filename: entry.filename)) else { return }
        var y = entry.startY
        for (i, h) in entry.pageHeights.enumerated() {
            if let page = pdf.page(at: i) { addPDFLayer(page: page, at: y, height: h) }
            y += h
        }
    }

    private func loadImageEntry(_ entry: InsertedImage) {
        guard let img = UIImage(contentsOfFile: store.imageURL(filename: entry.filename).path) else { return }
        let layer = makeImageLayer(image: img,
                                   frame: CGRect(x: 0, y: entry.startY, width: entry.width, height: entry.height))
        insertBelowDrawing(layer)
        imageLayers.append(layer)
    }

    // MARK: - Layer helpers

    @discardableResult
    private func addPDFLayer(page: PDFPage, at y: CGFloat, height: CGFloat? = nil) -> CGFloat {
        let bounds = page.bounds(for: .cropBox)
        let w      = canvasView.contentSize.width > 0 ? canvasView.contentSize.width : view.bounds.width
        let scale  = w / bounds.width
        let h      = height ?? bounds.height * scale
        let image  = renderPDFPage(page, width: w, height: h)

        let layer = CALayer()
        layer.frame    = CGRect(x: 0, y: y, width: w, height: h)
        layer.contents = image.cgImage
        layer.contentsGravity = .resizeAspect
        insertBelowDrawing(layer)
        pdfLayers.append(layer)
        return h
    }

    private func renderPDFPage(_ page: PDFPage, width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let b = page.bounds(for: .cropBox)
            let scale = width / b.width
            ctx.cgContext.translateBy(x: 0, y: height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .cropBox, to: ctx.cgContext)
        }
    }

    private func makeImageLayer(image: UIImage, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame           = frame
        layer.contents        = image.cgImage
        layer.contentsGravity = .resizeAspect
        layer.cornerRadius    = 6
        layer.masksToBounds   = true
        layer.borderWidth     = 0.5
        layer.borderColor     = UIColor.systemGray4.cgColor
        return layer
    }

    // Insert a CALayer below PencilKit's Metal drawing layer
    private func insertBelowDrawing(_ layer: CALayer) {
        canvasView.layer.insertSublayer(layer, at: 0)
    }

    private func nextInsertY() -> CGFloat {
        let drawingBottom = canvasView.drawing.bounds.maxY
        let pdfBottom     = document.insertedPDFs.last?.endY ?? 0
        let imgBottom     = document.insertedImages.last.map { $0.startY + $0.height } ?? 0
        let visBottom     = canvasView.contentOffset.y + canvasView.bounds.height
        return max(drawingBottom, pdfBottom, imgBottom, visBottom) + 40
    }
}

// MARK: - Math & Handwriting Recognition

extension InfiniteNotebookViewController {

    func scheduleScan() {
        guard document.mathEnabled else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            await self.performScan(mathOnly: true)
        }
    }

    func recogniseHandwriting() {
        Task { [weak self] in await self?.performScan(mathOnly: false) }
    }

    @MainActor
    private func performScan(mathOnly: Bool) async {
        let scale     = canvasView.zoomScale
        let visible   = CGRect(
            x: canvasView.contentOffset.x / scale,
            y: canvasView.contentOffset.y / scale,
            width:  canvasView.bounds.width  / scale,
            height: canvasView.bounds.height / scale
        )
        let drawing = canvasView.drawing
        guard !drawing.strokes.filter({ $0.renderBounds.intersects(visible) }).isEmpty else { return }

        guard let composite = compositeVisible(rect: visible, drawing: drawing) else { return }
        let obs = await runVision(on: composite)
        guard !obs.isEmpty else { return }

        clearResultLabels()

        for o in obs {
            guard let text = o.topCandidates(1).first?.string, !text.isEmpty else { continue }

            let vb   = o.boundingBox  // normalized, Y from bottom
            let docX = visible.minX + vb.minX * visible.width
            let docY = visible.minY + (1 - vb.maxY) * visible.height
            let docH = vb.height * visible.height

            if mathOnly {
                let expr = leftOfEquals(text)
                guard looksLikeMath(expr), case .success(let v) = evaluator.evaluate(expr) else { continue }
                addResultLabel("= \(fmt(v))", at: CGPoint(x: docX, y: docY + docH + 4), color: .systemBlue)
            } else {
                addResultLabel(text, at: CGPoint(x: docX, y: docY + docH + 4), color: .systemGreen)
            }
        }
    }

    private func compositeVisible(rect: CGRect, drawing: PKDrawing) -> UIImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let sc:  CGFloat = 1.5
        let size = CGSize(width: rect.width * sc, height: rect.height * sc)
        let ink  = drawing.image(from: rect, scale: sc)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func runVision(on image: UIImage) async -> [VNRecognizedTextObservation] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { r, _ in
                cont.resume(returning: (r.results as? [VNRecognizedTextObservation]) ?? [])
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: cg).perform([req])
            } catch {
                // perform failed — continuation must still be called exactly once
                cont.resume(returning: [])
            }
        }
    }

    private func addResultLabel(_ text: String, at pt: CGPoint, color: UIColor) {
        let lbl = PaddedLabel()
        lbl.text            = text
        lbl.font            = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        lbl.textColor       = color
        lbl.backgroundColor = color.withAlphaComponent(0.1)
        lbl.layer.cornerRadius  = 6
        lbl.layer.masksToBounds = true
        lbl.layer.borderWidth   = 0.5
        lbl.layer.borderColor   = color.withAlphaComponent(0.35).cgColor
        lbl.sizeToFit()
        lbl.frame.origin = pt
        canvasView.addSubview(lbl)
        lbl.alpha = 0
        UIView.animate(withDuration: 0.25) { lbl.alpha = 1 }
        resultLabels.append(lbl)
    }

    func clearResultLabels() {
        resultLabels.forEach { $0.removeFromSuperview() }
        resultLabels.removeAll()
    }

    // MARK: - Helpers

    private func looksLikeMath(_ t: String) -> Bool {
        let ops = CharacterSet(charactersIn: "+-*/×÷^%")
        return t.unicodeScalars.contains(where: ops.contains) &&
               t.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
    }
    private func leftOfEquals(_ t: String) -> String {
        t.range(of: "=").map { String(t[t.startIndex..<$0.lowerBound]) } ?? t
    }
    private func fmt(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e12 ? String(format: "%.0f", v) : String(format: "%g", v)
    }
}

// MARK: - PKCanvasViewDelegate

extension InfiniteNotebookViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onDrawingChanged?()
        extendIfNeeded()
        scheduleScan()
    }
}

// MARK: - PaddedLabel

private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}
