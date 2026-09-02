import UIKit
import PencilKit
import PDFKit
import Vision

extension Notification.Name {
    static let electroNoteDrawingBegan = Notification.Name("ElectroNote.DrawingBegan")
}

// MARK: - Main

final class InfiniteNotebookViewController: UIViewController {

    // MARK: - Constants
    static let initialHeight: CGFloat = NotebookDocument.initialHeight

    // MARK: - Views
    var canvasView  = PKCanvasView()
    let toolPicker  = PKToolPicker()

    // MARK: - Content layers & views (below the PencilKit Metal layer)
    private var paperBackgroundView = UIView()
    private var pageBreakContainer  = UIView()
    private var backgroundLayer = CALayer()
    private var pdfViews:    [UIImageView] = []
    private var imageViews:  [UIImageView] = []
    private var pdfLayers:   [CALayer] = []
    private var imageLayers: [CALayer] = []

    // MARK: - Transparent UIView handles for image interaction (finger-only)
    // Each handle mirrors the frame of the corresponding imageLayer in canvas content coords.
    private var imageHandles: [ImageHandleView] = []

    // MARK: - Sticky notes (UIView overlays positioned via KVO on scroll/zoom)
    private var stickyNoteViews: [UUID: StickyNoteView] = [:]
    private var scrollKVOObservers: [NSKeyValueObservation] = []

    // MARK: - Recognition banner (lives in self.view, fully outside PencilKit)
    private var bannerView: RecognitionBannerView?
    private var bannerDismissTask: Task<Void, Never>?
    private var lastScanRect: CGRect = .null
    private var lastScanItems: [RecognitionBannerView.Item] = []

    // MARK: - Math / handwriting
    private var scanTask: Task<Void, Never>?
    private var selectionOverlay: HandwritingSelectionOverlay?
    private var lastLassoPoints: [CGPoint] = []
    private let evaluator = MathEvaluator()

    // MARK: - Native text input
    private var nativeTextView: UITextView?
    private var nativeTextContentOrigin: CGPoint = .zero
    private lazy var nativeTextDelegate = NativeTextViewDelegate(vc: self)

    // MARK: - State
    private(set) var document = NotebookDocument()
    var store: NotebookDocumentStore!
    private var didLoad = false

    // MARK: - Callbacks
    var onDrawingChanged: (() -> Void)?

    // MARK: - Configurable

    var pencilOnly: Bool = true {
        didSet { applyDrawingPolicy() }
    }

    private func applyDrawingPolicy() {
        canvasView.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        // In pencil-only mode require 2 fingers to scroll — prevents palm from panning
        canvasView.panGestureRecognizer.minimumNumberOfTouches = pencilOnly ? 2 : 1
    }

    var mathEnabled: Bool {
        get { document.mathEnabled }
        set { document.mathEnabled = newValue; if !newValue { hideBanner() } }
    }

    var shapeSnapEnabled: Bool {
        get { document.shapeSnapEnabled }
        set { document.shapeSnapEnabled = newValue; store?.saveDocument(document) }
    }
    private var isSnappingShape = false
    private var shapeSnapTask: Task<Void, Never>?

    var background: BackgroundStyle {
        get { document.background }
        set { document.background = newValue; refreshBackground(); store?.saveDocument(document) }
    }

    var lineSpacing: LineSpacing {
        get { document.lineSpacing }
        set { document.lineSpacing = newValue; refreshBackground(); store?.saveDocument(document) }
    }

    var darkDrawingMode: Bool {
        get { document.darkDrawingMode }
        set {
            document.darkDrawingMode = newValue
            canvasView.overrideUserInterfaceStyle = newValue ? .dark : .light
            refreshBackground()
            store?.saveDocument(document)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        let dark = document.darkDrawingMode
        view.backgroundColor = dark ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                                    : UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)
        setupCanvas()
        setupToolPicker()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if canvasView.frame != view.bounds {
            canvasView.frame = view.bounds
        }
        let currentW = max(view.bounds.width, 834)
        if canvasView.contentSize.width != currentW && currentW > 0 {
            canvasView.contentSize.width = currentW
            updateBackgroundFrame()
        }
        if !didLoad {
            didLoad = true
            loadDocument()
        }
        centerCanvasContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
        applyDrawingPolicy()
        centerCanvasContent()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        save()
    }

    // MARK: - Setup

    private func setupCanvas() {
        let dark = document.darkDrawingMode
        view.backgroundColor = dark ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                                    : UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)

        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.minimumZoomScale = 0.25
        canvasView.maximumZoomScale = 8.0
        canvasView.drawingPolicy   = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque        = false
        canvasView.delegate        = self
        // 2-finger scroll in pencilOnly mode — prevents single palm touch from panning
        canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
        view.addSubview(canvasView)

        paperBackgroundView.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        paperBackgroundView.isUserInteractionEnabled = false
        canvasView.insertSubview(paperBackgroundView, at: 0)
    }

    private func setupToolPicker() {
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        toolPicker.addObserver(self)
    }

    // MARK: - Load

    private func loadDocument() {
        guard store != nil else { return }
        document = store.loadDocument()
        canvasView.drawing = store.loadDrawing()

        let drawingMaxY = canvasView.drawing.bounds.isNull ? 0 : canvasView.drawing.bounds.maxY
        let h = max(document.documentHeight, drawingMaxY + Self.initialHeight * 0.5)
        let w = max(view.bounds.width > 0 ? view.bounds.width : 834, 834)
        canvasView.contentSize = CGSize(width: w, height: h)

        canvasView.overrideUserInterfaceStyle = document.darkDrawingMode ? .dark : .light
        setupBackgroundLayer()
        refreshBackground()

        document.insertedPDFs.forEach   { loadPDFEntry($0) }
        document.insertedImages.forEach { loadImageEntry($0) }
        document.stickyNotes.forEach    { mountStickyNoteView($0) }

    }

    // MARK: - Background & Page Breaks

    private func setupBackgroundLayer() {
        paperBackgroundView.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        backgroundLayer.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        if backgroundLayer.superlayer == nil {
            canvasView.layer.insertSublayer(backgroundLayer, at: 0)
        }
        setupPageBreakDividers()
    }

    private func setupPageBreakDividers() {
        pageBreakContainer.isUserInteractionEnabled = false
        pageBreakContainer.backgroundColor = .clear
        if pageBreakContainer.superview == nil {
            paperBackgroundView.addSubview(pageBreakContainer)
        }
        updatePageBreakDividers()
    }

    private func updatePageBreakDividers() {
        pageBreakContainer.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        pageBreakContainer.subviews.forEach { $0.removeFromSuperview() }

        let width = canvasView.contentSize.width
        let pageH = width * 1.41421356 // Proportional ISO A4 ratio (1 : √2)
        let totalH = canvasView.contentSize.height
        let dark = document.darkDrawingMode

        var pageNum = 1
        var y = pageH
        while y < totalH {
            let divider = makePageBreakView(y: y, width: width, pageNumber: pageNum, dark: dark)
            pageBreakContainer.addSubview(divider)
            pageNum += 1
            y += pageH
        }
    }

    private func makePageBreakView(y: CGFloat, width: CGFloat, pageNumber: Int, dark: Bool) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: y - 10, width: width, height: 20))
        container.isUserInteractionEnabled = false

        // Dashed horizontal page break line
        let line = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 16, y: 10))
        path.addLine(to: CGPoint(x: width - 16, y: 10))
        line.path = path.cgPath
        line.strokeColor = (dark ? UIColor(white: 0.40, alpha: 0.5) : UIColor(white: 0.60, alpha: 0.6)).cgColor
        line.lineWidth = 1.0
        line.lineDashPattern = [6, 4]
        container.layer.addSublayer(line)

        // Pill badge in center with page break info
        let label = UILabel()
        label.text = "A4 Seite \(pageNumber) Ende"
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = dark ? UIColor(white: 0.70, alpha: 1) : UIColor(white: 0.40, alpha: 1)
        label.backgroundColor = dark ? UIColor(white: 0.18, alpha: 0.95) : UIColor(white: 0.96, alpha: 0.95)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.borderWidth = 0.5
        label.layer.borderColor = (dark ? UIColor(white: 0.35, alpha: 0.8) : UIColor(white: 0.75, alpha: 0.8)).cgColor
        label.clipsToBounds = true
        label.sizeToFit()

        let badgeW = label.frame.width + 16
        label.frame = CGRect(x: (width - badgeW) * 0.5, y: 1, width: badgeW, height: 18)
        container.addSubview(label)

        return container
    }

    // Called whenever background style or dark mode changes
    private func refreshBackground() {
        let dark = document.darkDrawingMode
        let deskColor = dark ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
                             : UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)
        view.backgroundColor = deskColor

        let paperBg = dark ? UIColor(white: 0.16, alpha: 1) : UIColor.white
        let line    = dark ? UIColor(white: 0.32, alpha: 1) : UIColor.systemGray4
        let pattern = UIColor(patternImage: makePattern(document.background, bg: paperBg, line: line))

        paperBackgroundView.backgroundColor = pattern
        paperBackgroundView.layer.cornerRadius = 4
        paperBackgroundView.layer.masksToBounds = true
        paperBackgroundView.layer.shadowColor = UIColor.black.cgColor
        paperBackgroundView.layer.shadowOpacity = dark ? 0.45 : 0.18
        paperBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)
        paperBackgroundView.layer.shadowRadius = 14
        paperBackgroundView.layer.borderWidth = 1.0
        paperBackgroundView.layer.borderColor = (dark ? UIColor(white: 0.28, alpha: 0.8) : UIColor(white: 0.80, alpha: 0.8)).cgColor

        backgroundLayer.backgroundColor = pattern.cgColor
        updatePageBreakDividers()
        centerCanvasContent()
    }

    private func updateBackgroundFrame() {
        paperBackgroundView.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        backgroundLayer.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        updatePageBreakDividers()
        centerCanvasContent()
    }

    private func centerCanvasContent() {
        let boundsSize = canvasView.bounds.size
        guard boundsSize.width > 0 && boundsSize.height > 0 else { return }

        let scaledWidth  = canvasView.contentSize.width * canvasView.zoomScale
        let scaledHeight = canvasView.contentSize.height * canvasView.zoomScale

        let offsetX = max((boundsSize.width - scaledWidth) * 0.5, 0)
        let offsetY = max((boundsSize.height - scaledHeight) * 0.5, 0)

        canvasView.contentInset = UIEdgeInsets(
            top: max(offsetY, 24),
            left: max(offsetX, 16),
            bottom: max(offsetY, 24),
            right: max(offsetX, 16)
        )
    }

    private func makePattern(_ style: BackgroundStyle, bg: UIColor, line: UIColor) -> UIImage {
        let sp = document.lineSpacing.points
        switch style {
        case .blank:   return solidColor(bg)
        case .lined:   return linedImage(spacing: sp, bg: bg, line: line)
        case .grid:    return gridImage(spacing: sp, bg: bg, line: line)
        case .dotted:  return dottedImage(spacing: sp, bg: bg, dot: line)
        case .cornell: return cornellImage(spacing: sp, bg: bg, line: line)
        }
    }

    private func solidColor(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func gridImage(spacing: CGFloat, bg: UIColor, line: UIColor) -> UIImage {
        let s = spacing
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            line.setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: s, y: 0)); ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.move(to: CGPoint(x: 0, y: s)); ctx.cgContext.addLine(to: CGPoint(x: s, y: s))
            ctx.cgContext.strokePath()
        }
    }

    private func linedImage(spacing: CGFloat, bg: UIColor, line: UIColor) -> UIImage {
        let s = spacing
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: s)).image { ctx in
            bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: s))
            line.withAlphaComponent(0.6).setStroke()
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: 0, y: s - 0.5))
            ctx.cgContext.addLine(to: CGPoint(x: 20, y: s - 0.5))
            ctx.cgContext.strokePath()
        }
    }

    private func dottedImage(spacing: CGFloat, bg: UIColor, dot: UIColor) -> UIImage {
        let s = spacing
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            bg.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            dot.setFill()
            ctx.cgContext.addEllipse(in: CGRect(x: s - 1.5, y: s - 1.5, width: 2.5, height: 2.5))
            ctx.cgContext.fillPath()
        }
    }

    private func cornellImage(spacing: CGFloat, bg: UIColor, line: UIColor) -> UIImage {
        // Dynamic A4 section matching current canvas width
        let w = canvasView.contentSize.width > 0 ? canvasView.contentSize.width : max(view.bounds.width, 834)
        let h = w * 1.41421356 // Proportional ISO A4
        let cueCol: CGFloat   = max(w * 0.28, 175)
        let summaryH: CGFloat = max(h * 0.18, 160)

        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            bg.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Strong structural lines
            line.setStroke()
            ctx.cgContext.setLineWidth(1.0)
            // Vertical divider (cue | notes)
            ctx.cgContext.move(to: CGPoint(x: cueCol, y: 0))
            ctx.cgContext.addLine(to: CGPoint(x: cueCol, y: h - summaryH))
            // Horizontal divider (notes | summary)
            ctx.cgContext.move(to: CGPoint(x: 0, y: h - summaryH))
            ctx.cgContext.addLine(to: CGPoint(x: w, y: h - summaryH))
            ctx.cgContext.strokePath()

            // Ruled lines across full width (subtle)
            line.withAlphaComponent(0.3).setStroke()
            ctx.cgContext.setLineWidth(0.5)
            var y: CGFloat = spacing
            while y < h - summaryH {
                ctx.cgContext.move(to: CGPoint(x: 0, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: w, y: y))
                y += spacing
            }
            ctx.cgContext.strokePath()
        }
    }

    // MARK: - Auto-extend

    private func extendIfNeeded() {
        let rawMaxY = canvasView.drawing.bounds.isNull ? 0 : canvasView.drawing.bounds.maxY
        let needed = rawMaxY + Self.initialHeight * 0.3
        guard needed > canvasView.contentSize.height else { return }
        let newH = needed + Self.initialHeight * 0.5
        canvasView.contentSize.height = newH
        updateBackgroundFrame()
        document.documentHeight = newH
        // Document height persisted by the ViewModel autosave timer — no immediate write needed here
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
        Task { @MainActor in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let pdfURL: URL
            do {
                pdfURL = try await DocumentConverter.shared.convertToPDF(sourceURL: url)
            } catch {
                pdfURL = url
            }

            let pdfAccessing = (pdfURL != url) ? pdfURL.startAccessingSecurityScopedResource() : false
            defer { if pdfAccessing { pdfURL.stopAccessingSecurityScopedResource() } }

            guard let filename = try? self.store.copyPDF(from: pdfURL) else { return }
            let storedURL = self.store.pdfURL(filename: filename)
            guard let pdf = PDFDocument(url: storedURL), pdf.pageCount > 0 else { return }

            let startY = self.nextInsertY()
            var y = startY
            var heights: [CGFloat] = []

            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let h = self.addPDFLayer(page: page, at: y)
                heights.append(h)
                y += h
            }

            let needed = y + Self.initialHeight * 0.3
            if needed > self.canvasView.contentSize.height {
                self.canvasView.contentSize.height = needed
                self.updateBackgroundFrame()
            }

            let entry = InsertedPDF(id: UUID(), filename: filename, startY: startY, pageHeights: heights)
            self.document.insertedPDFs.append(entry)
            self.document.documentHeight = self.canvasView.contentSize.height
            self.store.saveDocument(self.document)

            self.canvasView.setContentOffset(CGPoint(x: 0, y: max(0, startY - 40)), animated: true)
        }
    }

    func insertImage(_ image: UIImage) {
        guard let filename = try? store.saveImage(image) else { return }

        let startY  = nextInsertY()
        let w       = canvasView.contentSize.width
        let ratio   = image.size.height / image.size.width
        let h       = w * ratio

        let contentFrame = CGRect(x: 0, y: startY, width: w, height: h)
        let imgView = makeImageView(image: image, frame: contentFrame)
        if paperBackgroundView.superview != nil {
            canvasView.insertSubview(imgView, aboveSubview: paperBackgroundView)
        } else {
            canvasView.insertSubview(imgView, at: 0)
        }
        imageViews.append(imgView)
        imageLayers.append(imgView.layer)

        let needed = startY + h + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height {
            canvasView.contentSize.height = needed
            updateBackgroundFrame()
        }

        let entry = InsertedImage(id: UUID(), filename: filename,
                                  startY: startY, width: w, height: h)
        document.insertedImages.append(entry)
        addImageHandle(for: imgView.layer, at: contentFrame, documentIndex: document.insertedImages.count - 1)
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
        let contentFrame = CGRect(x: entry.startX, y: entry.startY,
                                  width: entry.width, height: entry.height)
        let imgView = makeImageView(image: img, frame: contentFrame)
        if paperBackgroundView.superview != nil {
            canvasView.insertSubview(imgView, aboveSubview: paperBackgroundView)
        } else {
            canvasView.insertSubview(imgView, at: 0)
        }
        imageViews.append(imgView)
        imageLayers.append(imgView.layer)
        let idx = document.insertedImages.firstIndex(where: { $0.id == entry.id }) ?? (imageViews.count - 1)
        addImageHandle(for: imgView.layer, at: contentFrame, documentIndex: idx)
    }

    // MARK: - Layer helpers

    @discardableResult
    private func addPDFLayer(page: PDFPage, at y: CGFloat, height: CGFloat? = nil) -> CGFloat {
        let bounds = page.bounds(for: .cropBox)
        let w      = canvasView.contentSize.width > 0 ? canvasView.contentSize.width : view.bounds.width
        let scale  = w / max(bounds.width, 1)
        let h      = height ?? (bounds.height * scale)
        let image  = renderPDFPage(page, width: w, height: h)

        let imgView = UIImageView(frame: CGRect(x: 0, y: y, width: w, height: h))
        imgView.image = image
        imgView.contentMode = .scaleAspectFit
        imgView.isUserInteractionEnabled = false // Allow pencil & handwriting to draw seamlessly on top
        imgView.backgroundColor = .white
        imgView.layer.shadowColor = UIColor.black.cgColor
        imgView.layer.shadowOpacity = 0.08
        imgView.layer.shadowOffset = CGSize(width: 0, height: 2)
        imgView.layer.shadowRadius = 4

        if paperBackgroundView.superview != nil {
            canvasView.insertSubview(imgView, aboveSubview: paperBackgroundView)
        } else {
            canvasView.insertSubview(imgView, at: 0)
        }
        pdfViews.append(imgView)
        pdfLayers.append(imgView.layer)
        return h
    }

    private func renderPDFPage(_ page: PDFPage, width: CGFloat, height: CGFloat) -> UIImage {
        let targetSize = CGSize(width: max(width, 100), height: max(height, 100))
        return page.thumbnail(of: targetSize, for: .cropBox)
    }

    private func makeImageView(image: UIImage, frame: CGRect) -> UIImageView {
        let imgView = UIImageView(frame: frame)
        imgView.image = image
        imgView.contentMode = .scaleAspectFit
        imgView.isUserInteractionEnabled = false
        imgView.clipsToBounds = true
        return imgView
    }

    private func nextInsertY() -> CGFloat {
        let drawingBottom = canvasView.drawing.bounds.isNull ? 0 : canvasView.drawing.bounds.maxY
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
        showSelectionOverlay()
    }

    // MARK: - Selection overlay

    private func showSelectionOverlay() {
        let overlay = HandwritingSelectionOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        selectionOverlay = overlay

        overlay.onCancel = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            self?.selectionOverlay = nil
        }
        overlay.onLassoSelected = { [weak self, weak overlay] points, viewRect in
            overlay?.removeFromSuperview()
            self?.selectionOverlay = nil
            guard let self else { return }

            // Convert from screen view coordinates to unscaled PKDrawing canvas coordinates
            let scale = max(self.canvasView.zoomScale, 0.01)
            let offsetX = self.canvasView.contentOffset.x
            let offsetY = self.canvasView.contentOffset.y

            let contentPoints = points.map { pt in
                CGPoint(x: (pt.x + offsetX) / scale, y: (pt.y + offsetY) / scale)
            }
            let contentRect = CGRect(
                x: (viewRect.minX + offsetX) / scale,
                y: (viewRect.minY + offsetY) / scale,
                width: max(viewRect.width / scale, 20),
                height: max(viewRect.height / scale, 20)
            )

            self.lastLassoPoints = contentPoints
            Task { await self.recogniseInRegion(contentRect: contentRect, lassoPoints: contentPoints) }
        }

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
    }

    @MainActor
    private func recogniseInRegion(contentRect: CGRect, lassoPoints: [CGPoint] = []) async {
        let lassoPolygon = UIBezierPath()
        if let first = lassoPoints.first {
            lassoPolygon.move(to: first)
            for pt in lassoPoints.dropFirst() { lassoPolygon.addLine(to: pt) }
            lassoPolygon.close()
        }

        let relevantStrokes = canvasView.drawing.strokes.filter { stroke in
            if !lassoPoints.isEmpty {
                let mid = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
                return lassoPolygon.contains(mid) || contentRect.contains(stroke.renderBounds) || contentRect.intersects(stroke.renderBounds)
            } else {
                return contentRect.intersects(stroke.renderBounds)
            }
        }

        let scanRect: CGRect
        if !relevantStrokes.isEmpty {
            let strokeUnion = relevantStrokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
            scanRect = strokeUnion.insetBy(dx: -25, dy: -25)
        } else {
            scanRect = contentRect.insetBy(dx: -25, dy: -25)
        }

        guard let composite = compositeVisible(rect: scanRect, drawing: canvasView.drawing) else {
            showNoTextAlert()
            return
        }

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()

        let obs = await runVision(on: composite, mathMode: false)
        spinner.removeFromSuperview()

        var items: [RecognitionBannerView.Item] = []
        for o in obs {
            guard let text = o.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let expr = leftOfEquals(text)
            if looksLikeMath(expr), case .success(let v) = evaluator.evaluate(expr) {
                let formattedResult = fmt(v)
                let cleanText = text.trimmingCharacters(in: .whitespaces)
                let label = cleanText.contains("=") ? "\(cleanText) \(formattedResult)" : "\(cleanText) = \(formattedResult)"
                items.append(.init(label: label, copyText: formattedResult))
            } else {
                items.append(.init(label: text, copyText: text))
            }
        }

        guard !items.isEmpty else {
            showNoTextAlert()
            return
        }

        lastScanItems = items
        lastScanRect  = scanRect
        lastLassoPoints = lassoPoints
        showBanner(items: items, scanRect: scanRect)
    }

    private func showNoTextAlert() {
        let alert = UIAlertController(title: "Nichts erkannt",
                                      message: "Im ausgewählten Bereich wurde keine Handschrift gefunden.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @MainActor
    private func performScan(mathOnly: Bool) async {
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return }

        let scanRect: CGRect
        if mathOnly {
            guard let lastStroke = drawing.strokes.last else { return }
            let nearby = drawing.strokes.filter {
                $0.renderBounds.intersects(lastStroke.renderBounds.insetBy(dx: -350, dy: -80))
            }
            let union = nearby.reduce(lastStroke.renderBounds) { $0.union($1.renderBounds) }
            scanRect = union.insetBy(dx: -30, dy: -30)
        } else {
            let b = drawing.bounds
            guard !b.isNull, b.width > 0, b.height > 0 else { return }
            scanRect = b.insetBy(dx: -30, dy: -30)
        }

        guard let composite = compositeVisible(rect: scanRect, drawing: drawing) else { return }
        let obs = await runVision(on: composite, mathMode: mathOnly)
        guard !obs.isEmpty else { return }

        var items: [RecognitionBannerView.Item] = []

        for o in obs {
            guard let text = o.topCandidates(1).first?.string, !text.isEmpty else { continue }
            if mathOnly {
                let expr = leftOfEquals(text)
                if looksLikeMath(expr), case .success(let v) = evaluator.evaluate(expr) {
                    let formattedResult = fmt(v)
                    let cleanText = text.trimmingCharacters(in: .whitespaces)
                    let label = cleanText.contains("=") ? "\(cleanText) \(formattedResult)" : "\(cleanText) = \(formattedResult)"
                    items.append(.init(label: label, copyText: formattedResult))
                }
            } else {
                items.append(.init(label: text, copyText: text))
            }
        }

        guard !items.isEmpty else { return }
        lastScanItems = items
        lastScanRect  = scanRect
        showBanner(items: items, scanRect: scanRect)
    }

    private func compositeVisible(rect: CGRect, drawing: PKDrawing) -> UIImage? {
        let validCanvasRect = CGRect(origin: .zero, size: canvasView.contentSize)
        let validRect = rect.intersection(validCanvasRect)
        guard !validRect.isNull, validRect.width >= 10, validRect.height >= 10 else { return nil }
        let scale: CGFloat = 2.0
        let ink = drawing.image(from: validRect, scale: scale)
        guard ink.size.width > 0 && ink.size.height > 0 else { return nil }

        // Render black ink on pure white background for maximum Vision OCR contrast
        return UIGraphicsImageRenderer(size: ink.size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: ink.size))
            let tintedInk = ink.withRenderingMode(.alwaysTemplate)
            UIColor.black.set()
            tintedInk.draw(in: CGRect(origin: .zero, size: ink.size))
        }
    }

    private func runVision(on image: UIImage, mathMode: Bool = false) async -> [VNRecognizedTextObservation] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest { r, _ in
                    cont.resume(returning: (r.results as? [VNRecognizedTextObservation]) ?? [])
                }
                req.recognitionLevel = .accurate
                req.recognitionLanguages = ["de-DE", "en-US"]
                req.usesLanguageCorrection = !mathMode
                req.automaticallyDetectsLanguage = !mathMode
                do {
                    try VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]).perform([req])
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Auto-Scroll on Edge Writing
    func checkWritingEdgeAutoScroll() {
        // Bottom extension happens smoothly in extendIfNeeded without jumping contentOffset
        guard canvasView.zoomScale > 1.3 else { return }
        guard let lastStroke = canvasView.drawing.strokes.last else { return }
        let strokeBounds = lastStroke.renderBounds
        guard !strokeBounds.isNull && strokeBounds.width > 0 else { return }

        let strokeMaxPoint = CGPoint(x: strokeBounds.maxX, y: strokeBounds.midY)
        let visiblePoint = canvasView.convert(strokeMaxPoint, to: canvasView.superview ?? view)
        let bounds = canvasView.bounds

        // Right edge gentle pan only when deeply zoomed in and writing at far edge
        if visiblePoint.x > bounds.width - 50 {
            let maxOffsetX = max(0, canvasView.contentSize.width * canvasView.zoomScale - bounds.width)
            let stepX: CGFloat = bounds.width * 0.25
            let targetX = min(maxOffsetX, canvasView.contentOffset.x + stepX)
            if targetX > canvasView.contentOffset.x {
                canvasView.setContentOffset(CGPoint(x: targetX, y: canvasView.contentOffset.y), animated: true)
            }
        }
    }

    // MARK: - Recognition Banner

    func showBanner(items: [RecognitionBannerView.Item], scanRect: CGRect = .null) {
        hideBanner()

        let banner = RecognitionBannerView(items: items)
        banner.onDismiss = { [weak self] in self?.hideBanner() }
        banner.onInsertAsText = { [weak self] in
            guard let self else { return }
            let combined = self.lastScanItems.map(\.copyText).joined(separator: "\n")
            let origin: CGPoint
            if !self.lastScanRect.isNull {
                origin = CGPoint(x: self.lastScanRect.minX, y: self.lastScanRect.minY)
            } else {
                let off = self.canvasView.contentOffset
                let sc  = max(self.canvasView.zoomScale, 0.01)
                origin = CGPoint(x: 20, y: (off.y + 100) / sc)
            }
            self.insertTypedText(text: combined, fontSize: 22, contentOrigin: origin, addHandle: false)
            self.hideBanner()
        }
        banner.onReplaceHandwriting = { [weak self] in
            guard let self, !self.lastScanItems.isEmpty else { return }
            self.replaceHandwriting(in: self.lastScanRect, with: self.lastScanItems)
            self.hideBanner()
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        bannerView = banner
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 40)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            banner.alpha = 1
            banner.transform = .identity
        }

        bannerDismissTask?.cancel()
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hideBanner() }
        }
    }

    func hideBanner() {
        bannerDismissTask?.cancel()
        guard let banner = bannerView else { return }
        bannerView = nil
        UIView.animate(withDuration: 0.2) {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: 30)
        } completion: { _ in banner.removeFromSuperview() }
    }

    // MARK: - Math helpers

    private func looksLikeMath(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ops = CharacterSet(charactersIn: "+-*/×÷^%:=()√")
        let hasMathKeywords = trimmed.localizedCaseInsensitiveContains("sqrt") ||
                              trimmed.localizedCaseInsensitiveContains("sin") ||
                              trimmed.localizedCaseInsensitiveContains("cos") ||
                              trimmed.localizedCaseInsensitiveContains("tan") ||
                              trimmed.localizedCaseInsensitiveContains("log") ||
                              trimmed.localizedCaseInsensitiveContains("pi") ||
                              trimmed.contains("π")
        let hasDigits = trimmed.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
        let hasOps = trimmed.unicodeScalars.contains(where: ops.contains)
        return hasDigits && (hasOps || hasMathKeywords)
    }

    private func leftOfEquals(_ t: String) -> String {
        t.range(of: "=").map { String(t[t.startIndex..<$0.lowerBound]) } ?? t
    }
    private func fmt(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e12 ? String(format: "%.0f", v) : String(format: "%g", v)
    }
}

// MARK: - Text Conversion

extension InfiniteNotebookViewController {

    func renderTextAsImage(_ items: [RecognitionBannerView.Item], targetWidth: CGFloat? = nil) -> UIImage {
        let combined = items.map(\.copyText).joined(separator: "\n")
        return renderTypedText(combined, fontSize: 22, originX: 0)
    }

    func replaceHandwriting(in contentRect: CGRect, with items: [RecognitionBannerView.Item]) {
        let clearRect: CGRect
        if contentRect.isNull {
            let sc = max(canvasView.zoomScale, 0.01)
            let off = canvasView.contentOffset
            clearRect = CGRect(x: off.x / sc, y: off.y / sc,
                               width:  canvasView.bounds.width  / sc,
                               height: canvasView.bounds.height / sc)
        } else {
            clearRect = contentRect
        }

        let lassoPolygon = UIBezierPath()
        if let first = lastLassoPoints.first {
            lassoPolygon.move(to: first)
            for pt in lastLassoPoints.dropFirst() { lassoPolygon.addLine(to: pt) }
            lassoPolygon.close()
        }

        // Remove strokes whose midpoint or bounds are within the cleared area
        let remaining = canvasView.drawing.strokes.filter { stroke in
            if !lastLassoPoints.isEmpty {
                let mid = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
                return !lassoPolygon.contains(mid) && !clearRect.contains(stroke.renderBounds)
            } else {
                return !clearRect.intersects(stroke.renderBounds)
            }
        }
        canvasView.drawing = PKDrawing(strokes: remaining)

        let combinedText = items.map(\.copyText).joined(separator: "\n")
        let startX = max(clearRect.minX, 10)
        let startY = max(clearRect.minY, 0)
        let origin = CGPoint(x: startX, y: startY)
        insertTypedText(text: combinedText, fontSize: 22, contentOrigin: origin, addHandle: false)
    }
}

// MARK: - Typed Text Insertion

extension InfiniteNotebookViewController {

    func startTextPlacement(text: String, fontSize: CGFloat) {
        let overlay = TextPositionOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        overlay.onCancel = { [weak overlay] in
            overlay?.removeFromSuperview()
        }
        overlay.onPositionSelected = { [weak self, weak overlay] viewPoint in
            overlay?.removeFromSuperview()
            guard let self else { return }
            let contentPt = self.viewPointToContent(viewPoint)
            self.insertTypedText(text: text, fontSize: fontSize, contentOrigin: contentPt, addHandle: false)
        }

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
    }

    private func viewPointToContent(_ pt: CGPoint) -> CGPoint {
        let sc  = max(canvasView.zoomScale, 0.01)
        let off = canvasView.contentOffset
        return CGPoint(x: (pt.x + off.x) / sc, y: (pt.y + off.y) / sc)
    }

    private func insertTypedText(text: String, fontSize: CGFloat, contentOrigin: CGPoint, addHandle: Bool = false) {
        let img = renderTypedText(text, fontSize: fontSize, originX: contentOrigin.x)
        guard let filename = try? store.saveImage(img) else { return }

        let contentFrame = CGRect(x: contentOrigin.x, y: contentOrigin.y,
                                  width: img.size.width, height: img.size.height)
        let imgView = makeImageView(image: img, frame: contentFrame)
        imgView.layer.borderWidth = 0
        imgView.layer.borderColor = nil
        imgView.backgroundColor = .clear

        if paperBackgroundView.superview != nil {
            canvasView.insertSubview(imgView, aboveSubview: paperBackgroundView)
        } else {
            canvasView.insertSubview(imgView, at: 0)
        }
        imageViews.append(imgView)
        imageLayers.append(imgView.layer)

        let entry = InsertedImage(id: UUID(), filename: filename,
                                  startX: contentOrigin.x, startY: contentOrigin.y,
                                  width: img.size.width, height: img.size.height,
                                  textContent: text, fontSize: fontSize)
        document.insertedImages.append(entry)
        if addHandle {
            addImageHandle(for: imgView.layer, at: contentFrame, documentIndex: document.insertedImages.count - 1)
        }
        let needed = contentOrigin.y + img.size.height + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height { canvasView.contentSize.height = needed }
        document.documentHeight = canvasView.contentSize.height
        store.saveDocument(document)
    }

    private func renderTypedText(_ text: String, fontSize: CGFloat, originX: CGFloat) -> UIImage {
        let font  = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let textColor = document.darkDrawingMode ? UIColor.white : UIColor.black
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str   = NSAttributedString(string: text, attributes: attrs)

        // Available width from insertion point to right edge
        let available = max(canvasView.contentSize.width - originX - 10, 100)
        let w = min(available, canvasView.contentSize.width * 0.9)
        let textH = str.boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        let totalH = max(textH + 4, fontSize + 4)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: totalH), format: fmt).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: totalH))
            str.draw(in: CGRect(x: 0, y: 0, width: w, height: textH + 4))
        }
    }
}

// MARK: - Native Keyboard Text Input

extension InfiniteNotebookViewController {

    /// Called from the toolbar keyboard button via ViewModel → Representable bridge.
    /// Shows a tap-to-place overlay; after the user taps, a live UITextView appears there.
    func beginNativeTextInput() {
        let overlay = TextPositionOverlay()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        overlay.onCancel = { [weak overlay] in overlay?.removeFromSuperview() }
        overlay.onPositionSelected = { [weak self, weak overlay] viewPoint in
            overlay?.removeFromSuperview()
            self?.showNativeKeyboard(at: viewPoint)
        }
        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
    }

    private func showNativeKeyboard(at viewPoint: CGPoint) {
        let scale  = canvasView.zoomScale
        let offset = canvasView.contentOffset
        let contentX = (viewPoint.x + offset.x) / scale
        let contentY = (viewPoint.y + offset.y) / scale
        nativeTextContentOrigin = CGPoint(x: contentX, y: contentY)

        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 22)
        tv.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        tv.textColor = document.darkDrawingMode ? .white : .black
        tv.isScrollEnabled = false
        tv.textContainer.lineBreakMode = .byWordWrapping
        // Position at the tapped point in view coordinates
        let availableWidth = max(view.bounds.width - viewPoint.x - 16, 200)
        tv.frame = CGRect(x: viewPoint.x, y: viewPoint.y, width: min(availableWidth, 500), height: 52)
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
        tv.layer.cornerRadius = 4

        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Fertig", style: .done, target: self, action: #selector(commitNativeText))
        ]
        tv.inputAccessoryView = toolbar

        nativeTextView = tv
        tv.delegate = nativeTextDelegate
        view.addSubview(tv)
        tv.becomeFirstResponder()
    }

    @objc private func commitNativeText() {
        guard let tv = nativeTextView else { return }
        let text = tv.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tv.resignFirstResponder()
        tv.removeFromSuperview()
        nativeTextView = nil

        guard !text.isEmpty else { return }
        let fontSize = tv.font?.pointSize ?? 22
        insertTypedText(text: text, fontSize: fontSize, contentOrigin: nativeTextContentOrigin)
    }
}

// MARK: - Sticky Notes

extension InfiniteNotebookViewController {

    func addStickyNote() {
        let scale  = canvasView.zoomScale
        let offset = canvasView.contentOffset
        // Place at center of visible canvas content
        let cx = (offset.x + canvasView.bounds.width  / 2) / scale - StickyNoteView.noteSize.width / 2
        let cy = (offset.y + canvasView.bounds.height / 2) / scale - StickyNoteView.noteSize.height / 2
        let note = StickyNote(id: UUID(), text: "",
                              x: max(10, cx), y: max(10, cy),
                              colorIndex: document.stickyNotes.count % 4)
        document.stickyNotes.append(note)
        store.saveDocument(document)
        mountStickyNoteView(note)
    }

    func mountStickyNoteView(_ note: StickyNote) {
        let v = StickyNoteView(note: note)
        v.frame = CGRect(x: note.x, y: note.y,
                         width: StickyNoteView.noteSize.width,
                         height: StickyNoteView.noteSize.height)
        v.onMoved = { [weak self] contentOrigin in
            guard let self else { return }
            if let i = self.document.stickyNotes.firstIndex(where: { $0.id == note.id }) {
                self.document.stickyNotes[i].x = contentOrigin.x
                self.document.stickyNotes[i].y = contentOrigin.y
                self.store.saveDocument(self.document)
            }
        }
        v.onTextChanged = { [weak self] text in
            guard let self else { return }
            if let i = self.document.stickyNotes.firstIndex(where: { $0.id == note.id }) {
                self.document.stickyNotes[i].text = text
                self.store.saveDocument(self.document)
            }
        }
        v.onDrawingChanged = { [weak self] data in
            guard let self else { return }
            if let i = self.document.stickyNotes.firstIndex(where: { $0.id == note.id }) {
                self.document.stickyNotes[i].drawingData = data
                self.store.saveDocument(self.document)
            }
        }
        v.onDelete = { [weak self] in
            guard let self else { return }
            self.document.stickyNotes.removeAll { $0.id == note.id }
            self.stickyNoteViews[note.id]?.removeFromSuperview()
            self.stickyNoteViews.removeValue(forKey: note.id)
            self.store.saveDocument(self.document)
        }
        stickyNoteViews[note.id] = v
        canvasView.addSubview(v)
    }
}

// MARK: - Bookmarks

extension InfiniteNotebookViewController {

    func addBookmark() {
        let y = canvasView.contentOffset.y / canvasView.zoomScale
        let alert = UIAlertController(title: "Lesezeichen hinzufügen",
                                      message: "Name für diese Position",
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "z.B. Kapitel 2" }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Speichern", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            let bookmark = Bookmark(id: UUID(), title: title.isEmpty ? "Lesezeichen" : title, y: y)
            self.document.bookmarks.append(bookmark)
            self.store.saveDocument(self.document)
        })
        present(alert, animated: true)
    }

    func showBookmarkList() {
        let sheet = UIAlertController(title: "Lesezeichen", message: nil, preferredStyle: .actionSheet)
        for bm in document.bookmarks {
            sheet.addAction(UIAlertAction(title: bm.title, style: .default) { [weak self] _ in
                guard let self else { return }
                let targetY = bm.y * self.canvasView.zoomScale
                self.canvasView.setContentOffset(CGPoint(x: 0, y: max(0, targetY)), animated: true)
            })
        }
        if document.bookmarks.isEmpty {
            sheet.message = "Noch keine Lesezeichen.\nMit dem Lesezeichen-Button Position speichern."
        }
        sheet.addAction(UIAlertAction(title: "Schließen", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 0, height: 0)
        }
        present(sheet, animated: true)
    }

    func deleteBookmark(id: UUID) {
        document.bookmarks.removeAll { $0.id == id }
        store.saveDocument(document)
    }
}

// MARK: - PKCanvasViewDelegate

extension InfiniteNotebookViewController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isSnappingShape else { return }
        onDrawingChanged?()
        extendIfNeeded()
        checkWritingEdgeAutoScroll()
        scheduleScan()
        NotificationCenter.default.post(name: .electroNoteDrawingBegan, object: nil)
        scheduleShapeSnap()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerCanvasContent()
    }
}

// MARK: - Shape Snapping

extension InfiniteNotebookViewController {

    private func scheduleShapeSnap() {
        guard shapeSnapEnabled else { return }
        shapeSnapTask?.cancel()
        shapeSnapTask = Task { [weak self] in
            // Wait for the drawing event to settle (PKCanvasView may fire
            // canvasViewDrawingDidChange multiple times for one gesture).
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.performShapeSnap()
        }
    }

    @MainActor
    private func performShapeSnap() {
        let strokes = canvasView.drawing.strokes
        guard let last = strokes.last else { return }
        guard let (snapped, _) = ShapeSnapper.snap(last) else { return }

        isSnappingShape = true
        var updated = strokes
        updated[updated.count - 1] = snapped
        canvasView.drawing = PKDrawing(strokes: updated)
        isSnappingShape = false
    }
}

// MARK: - PKToolPickerObserver

extension InfiniteNotebookViewController: PKToolPickerObserver {
    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        applyDrawingPolicy()
    }
}

// MARK: - PDF Export

extension InfiniteNotebookViewController {

    func exportAsPDF(completion: @escaping (URL?) -> Void) {
        let drawing = canvasView.drawing
        let canvasWidth = canvasView.contentSize.width
        let canvasHeight = canvasView.contentSize.height

        guard canvasWidth > 0, canvasHeight > 0 else { completion(nil); return }

        // A4 page size in points
        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let scale = pageW / canvasWidth
        let totalPDFHeight = canvasHeight * scale
        let pageCount = max(1, Int(ceil(totalPDFHeight / pageH)))

        let filename = store.noteURL.deletingPathExtension().lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)_\(UUID().uuidString).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let data = renderer.pdfData { ctx in
            for page in 0..<pageCount {
                ctx.beginPage()
                let pdfCtx = ctx.cgContext
                // White background
                pdfCtx.setFillColor(UIColor.white.cgColor)
                pdfCtx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
                // Translate for current page
                pdfCtx.saveGState()
                pdfCtx.scaleBy(x: scale, y: scale)
                pdfCtx.translateBy(x: 0, y: -CGFloat(page) * pageH / scale)
                // Render background layer
                backgroundLayer.render(in: pdfCtx)
                // Render image layers
                imageLayers.forEach { $0.render(in: pdfCtx) }
                // Render PDF layers
                pdfLayers.forEach { $0.render(in: pdfCtx) }
                // Render drawing for this page's slice
                let pageContentRect = CGRect(
                    x: 0, y: CGFloat(page) * pageH / scale,
                    width: canvasWidth, height: pageH / scale
                )
                let inkImage = drawing.image(from: pageContentRect, scale: 2)
                inkImage.draw(in: CGRect(origin: .zero, size: CGSize(width: canvasWidth, height: pageH / scale)))
                pdfCtx.restoreGState()
            }
        }

        do {
            try data.write(to: tempURL)
            completion(tempURL)
        } catch {
            completion(nil)
        }
    }

    func presentExport() {
        exportAsPDF { [weak self] url in
            guard let self, let url = url else { return }
            let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            ac.popoverPresentationController?.sourceView = self.view
            ac.popoverPresentationController?.sourceRect = CGRect(
                x: self.view.bounds.midX, y: 100, width: 0, height: 0)
            self.present(ac, animated: true)
        }
    }
}

// MARK: - RecognitionBannerView

final class RecognitionBannerView: UIView {

    struct Item {
        let label: String
        let copyText: String
    }

    var onDismiss: (() -> Void)?
    var onInsertAsText: (() -> Void)?
    var onReplaceHandwriting: (() -> Void)?

    init(items: [Item]) {
        super.init(frame: .zero)
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 14
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let titleRow = makeRow()

        let titleLabel = UILabel()
        titleLabel.text = "Erkannt"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleRow.addArrangedSubview(titleLabel)

        let insertBtn = makeButton(title: "Als Text", image: "text.badge.plus", tint: .systemIndigo) { [weak self] in
            self?.onInsertAsText?()
        }
        titleRow.addArrangedSubview(insertBtn)

        let replaceBtn = makeButton(title: "Ersetzen", image: "pencil.slash", tint: .systemOrange) { [weak self] in
            self?.onReplaceHandwriting?()
        }
        titleRow.addArrangedSubview(replaceBtn)

        // Copy-all only if multiple items
        if items.count > 1 {
            let allText = items.map(\.copyText).joined(separator: "\n")
            let copyAll = makeButton(title: "Alles kopieren", tint: .systemBlue) { [allText] in
                UIPasteboard.general.string = allText
            }
            titleRow.addArrangedSubview(copyAll)
        }

        let close = makeButton(title: nil, image: "xmark.circle.fill", tint: .tertiaryLabel) { [weak self] in
            self?.onDismiss?()
        }
        titleRow.addArrangedSubview(close)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        stack.addArrangedSubview(titleRow)

        for item in items {
            let row = makeRow()

            let lbl = UILabel()
            lbl.text = item.label
            lbl.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
            lbl.numberOfLines = 2
            lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(lbl)

            let copyText = item.copyText
            let btn = makeButton(title: "Kopieren", tint: .systemBlue) {
                UIPasteboard.general.string = copyText
            }
            btn.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(btn)

            stack.addArrangedSubview(row)

            let sep = UIView()
            sep.backgroundColor = .separator
            sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            stack.addArrangedSubview(sep)
        }

        // Remove last separator
        if let last = stack.arrangedSubviews.last, last.backgroundColor == .separator {
            stack.removeArrangedSubview(last); last.removeFromSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeRow() -> UIStackView {
        let s = UIStackView()
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = 8
        return s
    }

    private func makeButton(title: String?, image: String? = nil, tint: UIColor, action: @escaping () -> Void) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        if let t = title { cfg.title = t }
        if let i = image  { cfg.image = UIImage(systemName: i) }
        cfg.baseForegroundColor = tint
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        let btn = UIButton(configuration: cfg)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }
}

// MARK: - NativeTextViewDelegate

private final class NativeTextViewDelegate: NSObject, UITextViewDelegate {
    weak var vc: InfiniteNotebookViewController?
    init(vc: InfiniteNotebookViewController) { self.vc = vc }

    func textViewDidChange(_ textView: UITextView) {
        // Auto-resize height to fit content while keeping the same width
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        textView.frame.size.height = max(52, size.height)
    }
}

// MARK: - ImageHandleView

/// A transparent UIView overlaid on an image CALayer.
/// Responds only to finger touches (not Apple Pencil) so the pencil still draws.
/// Provides drag-to-move and long-press-to-delete for inserted images.
final class ImageHandleView: UIView {

    /// Canvas-coordinate frame of the image (mirrors the CALayer.frame).
    var contentFrame: CGRect

    var onMoved: ((CGRect) -> Void)?   // called with new content-coord frame
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?

    // Keep a reference to the corresponding layer for live updates.
    private weak var mirroredLayer: CALayer?

    init(contentFrame: CGRect, layer: CALayer) {
        self.contentFrame   = contentFrame
        self.mirroredLayer  = layer
        super.init(frame: .zero)

        backgroundColor    = .clear
        isOpaque           = false
        isUserInteractionEnabled = true

        layer.borderWidth  = 0
        layer.borderColor  = UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        layer.cornerRadius = 4

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(pan)

        let dt = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        dt.numberOfTapsRequired = 2
        dt.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(dt)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        lp.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        lp.minimumPressDuration = 0.5
        addGestureRecognizer(lp)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Gesture handlers

    @objc private func handleDoubleTap() {
        onEdit?()
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview as? PKCanvasView else { return }
        let delta = gr.translation(in: sv)
        gr.setTranslation(.zero, in: sv)

        let scale = sv.zoomScale

        // Move the handle view in screen coordinates
        frame.origin.x += delta.x
        frame.origin.y += delta.y

        // Move the underlying CALayer in content coordinates
        let dx = delta.x / scale
        let dy = delta.y / scale
        contentFrame.origin.x += dx
        contentFrame.origin.y += dy
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirroredLayer?.frame = contentFrame
        CATransaction.commit()

        if gr.state == .ended || gr.state == .cancelled {
            onMoved?(contentFrame)
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        onEdit?()
    }

    // Only intercept finger touches — pencil passes through to PKCanvasView.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let touches = event?.allTouches else { return super.hitTest(point, with: event) }
        let hasOnlyFingers = touches.allSatisfy { $0.type != .pencil }
        guard hasOnlyFingers else { return nil }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Image Handle Management

extension InfiniteNotebookViewController {

    /// Creates a finger-only UIView handle over an image CALayer in the canvas.
    /// The handle is added as a subview of `canvasView` so its coordinate space
    /// matches the canvas content (no offset/zoom correction needed for positioning).
    func addImageHandle(for layer: CALayer, at contentFrame: CGRect, documentIndex: Int) {
        let handle = ImageHandleView(contentFrame: contentFrame, layer: layer)
        handle.frame = contentFrame   // canvasView subviews live in content coordinates
        canvasView.addSubview(handle)
        imageHandles.append(handle)

        handle.onEdit = { [weak self] in
            guard let self else { return }
            self.editInsertedElement(at: documentIndex)
        }

        handle.onMoved = { [weak self] newContentFrame in
            guard let self else { return }
            // Update the document entry
            guard documentIndex < self.document.insertedImages.count else { return }
            self.document.insertedImages[documentIndex].startX  = newContentFrame.minX
            self.document.insertedImages[documentIndex].startY  = newContentFrame.minY
            self.document.insertedImages[documentIndex].width   = newContentFrame.width
            self.document.insertedImages[documentIndex].height  = newContentFrame.height
            self.store.saveDocument(self.document)
        }

        handle.onDelete = { [weak self, weak handle] in
            guard let self, let handle else { return }
            // Find the index of this handle
            guard let hi = self.imageHandles.firstIndex(of: handle) else { return }
            // Remove the CALayer
            if hi < self.imageLayers.count { self.imageLayers[hi].removeFromSuperlayer() }
            // Remove from document
            if hi < self.document.insertedImages.count {
                let entry = self.document.insertedImages[hi]
                // Optionally delete the image file too
                try? FileManager.default.removeItem(at: self.store.imageURL(filename: entry.filename))
                self.document.insertedImages.remove(at: hi)
            }
            self.imageLayers.remove(at: hi)
            handle.removeFromSuperview()
            self.imageHandles.remove(at: hi)
            // Re-wire remaining handles' document indices
            self.rewireImageHandles()
            self.store.saveDocument(self.document)
        }
    }

    /// After a deletion the document indices shift; re-wire all handle closures.
    private func rewireImageHandles() {
        for (hi, handle) in imageHandles.enumerated() {
            handle.onEdit = { [weak self] in
                guard let self else { return }
                self.editInsertedElement(at: hi)
            }
            handle.onMoved = { [weak self] newContentFrame in
                guard let self else { return }
                guard hi < self.document.insertedImages.count else { return }
                self.document.insertedImages[hi].startX  = newContentFrame.minX
                self.document.insertedImages[hi].startY  = newContentFrame.minY
                self.document.insertedImages[hi].width   = newContentFrame.width
                self.document.insertedImages[hi].height  = newContentFrame.height
                self.store.saveDocument(self.document)
            }
            handle.onDelete = { [weak self, weak handle] in
                guard let self, let handle else { return }
                guard let hi2 = self.imageHandles.firstIndex(of: handle) else { return }
                if hi2 < self.imageLayers.count { self.imageLayers[hi2].removeFromSuperlayer() }
                if hi2 < self.document.insertedImages.count {
                    let entry = self.document.insertedImages[hi2]
                    try? FileManager.default.removeItem(at: self.store.imageURL(filename: entry.filename))
                    self.document.insertedImages.remove(at: hi2)
                }
                self.imageLayers.remove(at: hi2)
                handle.removeFromSuperview()
                self.imageHandles.remove(at: hi2)
                self.rewireImageHandles()
                self.store.saveDocument(self.document)
            }
        }
    }

    func editInsertedElement(at index: Int) {
        guard index < document.insertedImages.count else { return }
        let entry = document.insertedImages[index]

        let alert = UIAlertController(
            title: entry.textContent != nil ? "Text bearbeiten" : "Objekt",
            message: nil,
            preferredStyle: .actionSheet
        )

        if let text = entry.textContent {
            alert.addAction(UIAlertAction(title: "Text bearbeiten", style: .default) { [weak self] _ in
                self?.promptEditText(at: index, currentText: text, fontSize: entry.fontSize ?? 22)
            })
        }

        alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
            guard let self, index < self.imageHandles.count else { return }
            self.imageHandles[index].onDelete?()
        })
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))

        if let pop = alert.popoverPresentationController, index < imageHandles.count {
            pop.sourceView = imageHandles[index]
            pop.sourceRect = imageHandles[index].bounds
        }
        present(alert, animated: true)
    }

    private func promptEditText(at index: Int, currentText: String, fontSize: CGFloat) {
        let alert = UIAlertController(title: "Text bearbeiten", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentText
            tf.placeholder = "Text eingeben…"
            tf.font = UIFont.systemFont(ofSize: 18)
            tf.autocapitalizationType = .sentences
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Speichern", style: .default) { [weak self] _ in
            guard let self,
                  let newText = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newText.isEmpty else { return }
            self.updateInsertedText(at: index, newText: newText, fontSize: fontSize)
        })
        present(alert, animated: true)
    }

    func updateInsertedText(at index: Int, newText: String, fontSize: CGFloat) {
        guard index < document.insertedImages.count,
              index < imageLayers.count,
              index < imageHandles.count else { return }

        let entry = document.insertedImages[index]
        let newImg = renderTypedText(newText, fontSize: fontSize, originX: entry.startX)
        guard let newFilename = try? store.saveImage(newImg) else { return }

        try? FileManager.default.removeItem(at: store.imageURL(filename: entry.filename))

        let newFrame = CGRect(x: entry.startX, y: entry.startY, width: newImg.size.width, height: newImg.size.height)

        let layer = imageLayers[index]
        layer.contents = newImg.cgImage
        layer.frame = newFrame

        let handle = imageHandles[index]
        handle.frame = newFrame
        handle.contentFrame = newFrame

        document.insertedImages[index].filename = newFilename
        document.insertedImages[index].width = newImg.size.width
        document.insertedImages[index].height = newImg.size.height
        document.insertedImages[index].textContent = newText
        document.insertedImages[index].fontSize = fontSize

        store.saveDocument(document)
    }
}
