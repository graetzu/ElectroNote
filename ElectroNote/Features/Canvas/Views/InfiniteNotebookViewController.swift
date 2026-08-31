import UIKit
import PencilKit
import PDFKit
import Vision

// MARK: - Main class

final class InfiniteNotebookViewController: UIViewController {

    // MARK: - Constants
    static let pageW: CGFloat = NotebookDocument.pageWidth
    static let pageH: CGFloat = NotebookDocument.pageHeight

    // MARK: - UI
    let scrollView   = UIScrollView()
    let contentView  = UIView()
    var canvasView   = FixedPKCanvasView()
    let toolPicker   = PKToolPicker()

    // MARK: - Inline math/text results
    private var resultViews: [(view: UIView, id: UUID)] = []
    private var scanTask: Task<Void, Never>?

    // MARK: - Services
    private let evaluator  = MathEvaluator()

    // MARK: - State
    private(set) var document = NotebookDocument()
    var store: NotebookDocumentStore!
    private var layoutDone = false

    // MARK: - Callbacks
    var onDrawingChanged: (() -> Void)?

    // MARK: - Configurable

    var pencilOnly: Bool = true {
        didSet { canvasView.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput }
    }

    var mathEnabled: Bool {
        get { document.mathEnabled }
        set {
            document.mathEnabled = newValue
            if !newValue { clearResultViews() }
        }
    }

    var background: BackgroundStyle {
        get { document.background }
        set {
            document.background = newValue
            applyBackground(newValue)
            store?.saveDocument(document)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        setupScrollView()
        setupContentView()
        setupCanvas()
        setupToolPicker()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
        if !layoutDone {
            layoutDone = true
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

    private func setupScrollView() {
        view.addSubview(scrollView)
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = UIColor.systemGroupedBackground
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator   = true
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 1.0
        scrollView.bouncesZoom = false
    }

    private func setupContentView() {
        scrollView.addSubview(contentView)
        contentView.backgroundColor = .white
    }

    private func setupCanvas() {
        canvasView.isScrollEnabled = false
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        canvasView.bouncesZoom = false
        canvasView.bounces = false
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.delegate = self
        contentView.addSubview(canvasView)
    }

    private func setupToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
    }

    private func updateLayout() {
        let h      = document.documentHeight
        let vw     = view.bounds.width
        let hInset = max(0, (vw - Self.pageW) / 2)

        // Vertical padding only — horizontal layout via contentView.frame.origin.x
        scrollView.contentInset = UIEdgeInsets(top: 40, left: 0, bottom: 120, right: 0)
        // Content area is full screen width so horizontal scrolling is disabled
        scrollView.contentSize = CGSize(width: vw, height: h)

        // A4 content is centered inside the full-width scroll area
        contentView.frame = CGRect(x: hInset, y: 0, width: Self.pageW, height: h)
        canvasView.frame  = contentView.bounds
    }

    private func loadDocument() {
        guard store != nil else { return }
        document = store.loadDocument()
        applyBackground(document.background)
        canvasView.drawing = store.loadDrawing()
        document.insertedPDFs.forEach   { loadPDFImages($0) }
        document.insertedImages.forEach { loadInsertedImage($0) }
        updateLayout()
    }

    // MARK: - Auto-extend

    private func extendIfNeeded() {
        let bottom = canvasView.drawing.bounds.maxY
        guard bottom > document.documentHeight * 0.8 else { return }
        let newH = document.documentHeight + Self.pageH * 10
        document.documentHeight = newH
        updateLayout()
        store?.saveDocument(document)
    }

    // MARK: - Save

    func save() {
        store?.saveDrawing(canvasView.drawing)
        store?.saveDocument(document)
    }
}

// MARK: - Background

extension InfiniteNotebookViewController {

    private func applyBackground(_ style: BackgroundStyle) {
        contentView.backgroundColor = UIColor(patternImage: makePattern(style))
    }

    private func makePattern(_ style: BackgroundStyle) -> UIImage {
        switch style {
        case .blank:  return solidWhite()
        case .lined:  return linedImage()
        case .grid:   return gridImage()
        case .dotted: return dottedImage()
        }
    }

    private func solidWhite() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func gridImage() -> UIImage {
        let s: CGFloat = 28
        let line = UIColor.systemGray4
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: s, height: s))
            line.setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: s, y: 0));  ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.move(to: CGPoint(x: 0, y: s));  ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.strokePath()
        }
    }

    private func linedImage() -> UIImage {
        let s: CGFloat = 32
        let line = UIColor.systemBlue.withAlphaComponent(0.2)
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: 20, height: s))
            line.setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: 0, y: s - 0.5))
            ctx.cgContext.addLine(to: CGPoint(x: 20, y: s - 0.5))
            ctx.cgContext.strokePath()
        }
    }

    private func dottedImage() -> UIImage {
        let s: CGFloat = 26
        let dot = UIColor.systemGray3
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: s, height: s))
            dot.setFill()
            ctx.cgContext.addEllipse(in: CGRect(x: s - 1.5, y: s - 1.5, width: 2.5, height: 2.5))
            ctx.cgContext.fillPath()
        }
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

        let startY = currentInsertY()
        var y = startY
        var heights: [CGFloat] = []

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let h = renderAndAdd(page: page, at: y)
            heights.append(h)
            y += h
        }

        extendDocumentIfNeeded(to: y + Self.pageH * 2)

        let entry = InsertedPDF(id: UUID(), filename: filename, startY: startY, pageHeights: heights)
        document.insertedPDFs.append(entry)
        store.saveDocument(document)

        scrollTo(y: startY)
    }

    func insertImage(_ image: UIImage, caption: String = "") {
        guard let filename = try? store.saveImage(image) else { return }
        let startY = currentInsertY()
        let ratio  = image.size.height / image.size.width
        let w      = Self.pageW * 0.85
        let h      = w * ratio

        let iv = UIImageView(image: image)
        iv.frame = CGRect(x: (Self.pageW - w) / 2, y: startY, width: w, height: h)
        iv.contentMode   = .scaleAspectFit
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.layer.borderWidth = 0.5
        iv.layer.borderColor = UIColor.systemGray4.cgColor
        contentView.insertSubview(iv, belowSubview: canvasView)

        extendDocumentIfNeeded(to: startY + h + Self.pageH)

        let entry = InsertedImage(id: UUID(), filename: filename,
                                  startY: startY, width: w, height: h)
        document.insertedImages.append(entry)
        store.saveDocument(document)

        scrollTo(y: startY)
    }

    // MARK: - Load on open

    private func loadPDFImages(_ entry: InsertedPDF) {
        let pdfURL = store.pdfURL(filename: entry.filename)
        guard let pdf = PDFDocument(url: pdfURL) else { return }
        var y = entry.startY
        for (i, h) in entry.pageHeights.enumerated() {
            guard let page = pdf.page(at: i) else { y += h; continue }
            let scale = Self.pageW / page.bounds(for: .cropBox).width
            let img   = renderPDFPage(page, scale: scale)
            let iv    = UIImageView(image: img)
            iv.frame  = CGRect(x: 0, y: y, width: Self.pageW, height: h)
            iv.contentMode = .scaleAspectFit
            contentView.insertSubview(iv, belowSubview: canvasView)
            y += h
        }
    }

    private func loadInsertedImage(_ entry: InsertedImage) {
        guard let img = UIImage(contentsOfFile: store.imageURL(filename: entry.filename).path) else { return }
        let iv = UIImageView(image: img)
        iv.frame = CGRect(x: (Self.pageW - entry.width) / 2, y: entry.startY,
                          width: entry.width, height: entry.height)
        iv.contentMode = .scaleAspectFit
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.layer.borderWidth = 0.5
        iv.layer.borderColor = UIColor.systemGray4.cgColor
        contentView.insertSubview(iv, belowSubview: canvasView)
    }

    // MARK: - Helpers

    @discardableResult
    private func renderAndAdd(page: PDFPage, at y: CGFloat) -> CGFloat {
        let bounds = page.bounds(for: .cropBox)
        let scale  = Self.pageW / bounds.width
        let h      = bounds.height * scale
        let img    = renderPDFPage(page, scale: scale)
        let iv     = UIImageView(image: img)
        iv.frame   = CGRect(x: 0, y: y, width: Self.pageW, height: h)
        iv.contentMode = .scaleAspectFit
        contentView.insertSubview(iv, belowSubview: canvasView)
        return h
    }

    private func renderPDFPage(_ page: PDFPage, scale: CGFloat) -> UIImage {
        let b = page.bounds(for: .cropBox)
        let size = CGSize(width: b.width * scale, height: b.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .cropBox, to: ctx.cgContext)
        }
    }

    private func currentInsertY() -> CGFloat {
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
        let allBottom = max(
            canvasView.drawing.bounds.maxY,
            document.insertedPDFs.last?.endY ?? 0,
            (document.insertedImages.last.map { $0.startY + $0.height } ?? 0)
        )
        return max(visibleBottom, allBottom) + 20
    }

    private func extendDocumentIfNeeded(to y: CGFloat) {
        guard y > document.documentHeight else { return }
        document.documentHeight = y + Self.pageH * 2
        updateLayout()
    }

    private func scrollTo(y: CGFloat) {
        let offset = CGPoint(x: 0, y: max(0, y - 60))
        scrollView.setContentOffset(offset, animated: true)
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
        Task { [weak self] in
            await self?.performScan(mathOnly: false)
        }
    }

    @MainActor
    private func performScan(mathOnly: Bool) async {
        let visible = scrollView.convert(scrollView.bounds, to: contentView)
        let drawing = canvasView.drawing

        guard !drawing.strokes.filter({ $0.renderBounds.intersects(visible) }).isEmpty else { return }

        let image = compositeImage(rect: visible, drawing: drawing)
        let observations = await runVision(on: image)
        guard !observations.isEmpty else { return }

        clearResultViews()

        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { continue }

            let vb   = obs.boundingBox                     // Vision: normalised, Y from bottom
            let docX = visible.minX + vb.minX * visible.width
            let docY = visible.minY + (1 - vb.maxY) * visible.height
            let docH = vb.height * visible.height

            if mathOnly {
                let expr = leftOfEquals(text)
                guard looksLikeMath(expr),
                      case .success(let value) = evaluator.evaluate(expr)
                else { continue }
                addResultLabel("= \(formatValue(value))", at: CGPoint(x: docX, y: docY + docH + 4), color: .systemBlue)
            } else {
                addResultLabel(text, at: CGPoint(x: docX, y: docY + docH + 4), color: .systemGreen)
            }
        }
    }

    private func compositeImage(rect: CGRect, drawing: PKDrawing) -> UIImage {
        let scale: CGFloat = 1.5
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let drawingImg = drawing.image(from: rect, scale: scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            drawingImg.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func runVision(on image: UIImage) async -> [VNRecognizedTextObservation] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, _ in
                cont.resume(returning: (request.results as? [VNRecognizedTextObservation]) ?? [])
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cgImage).perform([req])
        }
    }

    private func addResultLabel(_ text: String, at origin: CGPoint, color: UIColor) {
        let label = PaddedLabel()
        label.text = text
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.1)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.layer.borderWidth  = 0.5
        label.layer.borderColor  = color.withAlphaComponent(0.35).cgColor
        label.insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: min(origin.x, Self.pageW - label.frame.width - 8),
            y: origin.y
        )
        contentView.addSubview(label)
        label.alpha = 0
        UIView.animate(withDuration: 0.25) { label.alpha = 1 }
        resultViews.append((view: label, id: UUID()))
    }

    func clearResultViews() {
        resultViews.forEach { $0.view.removeFromSuperview() }
        resultViews.removeAll()
    }

    // MARK: - Helpers

    private func looksLikeMath(_ text: String) -> Bool {
        let ops = CharacterSet(charactersIn: "+-*/×÷^%")
        return text.unicodeScalars.contains(where: ops.contains) &&
               text.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
    }

    private func leftOfEquals(_ text: String) -> String {
        if let r = text.range(of: "=") { return String(text[text.startIndex..<r.lowerBound]) }
        return text
    }

    private func formatValue(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e12 { return String(format: "%.0f", v) }
        return String(format: "%g", v)
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

// MARK: - UIScrollViewDelegate

extension InfiniteNotebookViewController: UIScrollViewDelegate {}

// MARK: - PaddedLabel helper

private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}

// MARK: - FixedPKCanvasView

/// PKCanvasView subclass that prevents internal scroll and zoom so that the
/// outer UIScrollView has full control over navigation.
final class FixedPKCanvasView: PKCanvasView {

    // Block any attempt to change the zoom scale
    override var zoomScale: CGFloat {
        get { 1.0 }
        set { }
    }
    override func setZoomScale(_ scale: CGFloat, animated: Bool) { }

    // Block any attempt to scroll the canvas internally
    override var contentOffset: CGPoint {
        get { .zero }
        set { }
    }
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) { }
}
