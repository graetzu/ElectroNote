import UIKit
import PencilKit
import PDFKit
import Vision

extension Notification.Name {
    static let electroNoteDrawingBegan = Notification.Name("ElectroNote.DrawingBegan")
    static let electroNoteInsertFileIntoOpenDocument = Notification.Name("ElectroNote.InsertFileIntoOpenDocument")
    static let electroNoteReloadCurrentPDF = Notification.Name("ElectroNote.ReloadCurrentPDF")
}

// MARK: - Main

final class InfiniteNotebookViewController: UIViewController {

    // MARK: - Constants
    static let initialHeight: CGFloat = NotebookDocument.initialHeight

    // MARK: - Views
    var canvasView  = PKCanvasView()
    let toolPicker  = PKToolPicker()

    // MARK: - Content layers & views (below the PencilKit Metal layer)
    private var paperBackgroundView = PaperBackgroundContainerView()
    private var pageBreakContainer  = UIView()
    private var pdfViews:    [UIImageView] = []
    private var pdfLayers:   [CALayer] = []

    // MARK: - Inserted images & text elements keyed by document entry ID (safe)
    private var imageViews:   [UUID: UIImageView]     = [:]
    private var imageLayers:  [UUID: CALayer]         = [:]
    private var imageHandles: [UUID: ImageHandleView] = [:]

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

    // MARK: - Transform & Selection Tools (Markieren, Verschieben, Drehen, Vergrößern)
    var currentCanvasToolType: CanvasToolType = .pen
    private var activeTransformBox: UniversalTransformBox?
    private var lassoOverlay: LassoCanvasOverlay?
    private var canvasLongPress: UILongPressGestureRecognizer?
    private var longPressInitialTouch: CGPoint?
    private var longPressStartCenter: CGPoint?
    private var isLongPressDragging: Bool = false

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
        // In pencilOnly mode (Standard):
        // - 1 finger moves / scrolls smoothly across the canvas
        // - Apple Pencil writes with zero lag
        // - 2 fingers pinch to zoom and pan
        // In anyInput mode (Finger & Stift):
        // - 1 finger or pencil writes
        // - 2 fingers scroll and pinch to zoom
        canvasView.panGestureRecognizer.minimumNumberOfTouches = pencilOnly ? 1 : 2
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

    // MARK: - Keyboard Shortcuts & Undo / Redo

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Einfügen", action: #selector(handleKeyboardPaste), input: "v", modifierFlags: .command),
            UIKeyCommand(title: "Kopieren", action: #selector(handleKeyboardCopy), input: "c", modifierFlags: .command),
            UIKeyCommand(title: "Rückgängig", action: #selector(handleKeyboardUndo), input: "z", modifierFlags: .command),
            UIKeyCommand(title: "Wiederholen", action: #selector(handleKeyboardRedo), input: "z", modifierFlags: [.command, .shift])
        ]
    }

    @objc private func handleKeyboardPaste() {
        pasteFromClipboard()
    }

    @objc private func handleKeyboardCopy() {
        copyLassoSelection()
    }

    @objc private func handleKeyboardUndo() {
        undoAction()
    }

    @objc private func handleKeyboardRedo() {
        redoAction()
    }

    func undoAction() {
        canvasView.undoManager?.undo()
        onDrawingChanged?()
        store?.saveDrawing(canvasView.drawing)
        store?.saveDocument(document)
    }

    func redoAction() {
        canvasView.undoManager?.redo()
        onDrawingChanged?()
        store?.saveDrawing(canvasView.drawing)
        store?.saveDocument(document)
    }

    func registerCustomUndo(actionName: String? = nil, _ action: @escaping () -> Void) {
        guard let undoManager = canvasView.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            action()
            self?.onDrawingChanged?()
        }
        if let actionName {
            undoManager.setActionName(actionName)
        }
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
        canvasView.bouncesZoom = true
        canvasView.pinchGestureRecognizer?.isEnabled = true
        canvasView.backgroundColor = .clear
        canvasView.isOpaque        = false
        canvasView.delegate        = self
        let initialColor = dark ? UIColor.white : UIColor.black
        canvasView.tool            = PKInkingTool(.pen, color: initialColor, width: 3.0)
        applyDrawingPolicy()
        view.addSubview(canvasView)

        paperBackgroundView.layer.anchorPoint = .zero
        paperBackgroundView.layer.position = .zero
        paperBackgroundView.bounds = CGRect(origin: .zero, size: canvasView.contentSize)
        paperBackgroundView.isUserInteractionEnabled = true
        canvasView.insertSubview(paperBackgroundView, at: 0)

        setupCanvasLongPress()
        setupCanvasTapToDeselect()
        setupExternalFileObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        let zoom = max(canvasView.zoomScale, 0.01)
        let unscaledSize = CGSize(
            width: canvasView.contentSize.width / zoom,
            height: canvasView.contentSize.height / zoom
        )
        paperBackgroundView.bounds = CGRect(origin: .zero, size: unscaledSize)
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
        let width = paperBackgroundView.bounds.width
        let totalH = paperBackgroundView.bounds.height
        guard width > 0 && totalH > 0 else { return }

        pageBreakContainer.frame = CGRect(origin: .zero, size: CGSize(width: width, height: totalH))
        pageBreakContainer.subviews.forEach { $0.removeFromSuperview() }

        let pageH = width * 1.41421356 // Proportional ISO A4 ratio (1 : √2)
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

        updatePageBreakDividers()
        centerCanvasContent()
    }

    private func updateBackgroundFrame() {
        let zoom = max(canvasView.zoomScale, 0.01)
        let unscaledSize = CGSize(
            width: canvasView.contentSize.width / zoom,
            height: canvasView.contentSize.height / zoom
        )
        paperBackgroundView.transform = .identity
        paperBackgroundView.bounds = CGRect(origin: .zero, size: unscaledSize)
        paperBackgroundView.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        lassoOverlay?.frame = CGRect(origin: .zero, size: canvasView.contentSize)
        updatePageBreakDividers()
        centerCanvasContent()
    }

    private func centerCanvasContent() {
        let boundsSize = canvasView.bounds.size
        guard boundsSize.width > 0 && boundsSize.height > 0 else { return }

        // canvasView.contentSize is already scaled by zoomScale in UIScrollView
        let scaledWidth  = canvasView.contentSize.width
        let scaledHeight = canvasView.contentSize.height

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

    func setupExternalFileObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalFileInsertion(_:)),
            name: .electroNoteInsertFileIntoOpenDocument,
            object: nil
        )
    }

    @objc private func handleExternalFileInsertion(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? URL else { return }
        if let targetPath = note.userInfo?["targetPath"] as? String,
           targetPath != store.noteURL.path {
            return
        }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "tiff", "webp"].contains(ext),
           let img = UIImage(contentsOfFile: url.path) {
            insertImage(img)
        } else {
            insertPDF(from: url)
        }
    }

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
            let docW = max(self.canvasView.contentSize.width, 834)
            let pageMargin: CGFloat = 20
            let availableW = docW - pageMargin * 2
            var heights: [CGFloat] = []

            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let b = page.bounds(for: .cropBox)
                let pageW = min(availableW, b.width > 0 ? b.width : 595)
                let scale = pageW / max(b.width, 1)
                let pageH = (b.height > 0 ? b.height : 842) * scale
                heights.append(pageH)

                let img = self.renderPDFPage(page, width: pageW, height: pageH)
                if let imgFilename = try? self.store.saveImage(img) {
                    let pageId = UUID()
                    let startX: CGFloat = max(pageMargin, (docW - pageW) / 2)
                    let entry = InsertedImage(id: pageId, filename: imgFilename, startX: startX, startY: y, width: pageW, height: pageH)
                    self.document.insertedImages.append(entry)
                    self.loadImageEntry(entry)
                } else {
                    self.addPDFLayer(page: page, at: y, height: pageH)
                }
                y += pageH + 24
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
            self.showToastBanner(text: "PDF eingefügt (\(pdf.pageCount) \(pdf.pageCount == 1 ? "Seite" : "Seiten"))", icon: "doc.text")
        }
    }

    func insertImage(_ image: UIImage, at explicitOrigin: CGPoint? = nil, registerUndoAction: Bool = true) {
        guard image.size.width > 0 && image.size.height > 0 else { return }
        guard let filename = try? store.saveImage(image) else { return }

        let sc = max(canvasView.zoomScale, 0.01)
        let off = canvasView.contentOffset

        let maxW = explicitOrigin != nil ? min(canvasView.contentSize.width * 0.7, image.size.width) : min(canvasView.contentSize.width * 0.8, max(image.size.width, 280))
        let ratio = image.size.height / max(image.size.width, 1)
        let w = min(maxW, canvasView.contentSize.width - 40)
        let h = w * ratio

        let startX: CGFloat = explicitOrigin?.x ?? max(20, (off.x + (canvasView.bounds.width - w * sc) / 2) / sc)
        let startY: CGFloat = explicitOrigin?.y ?? max(20, (off.y + 40) / sc)

        let id = UUID()
        let contentFrame = CGRect(x: startX, y: startY, width: w, height: h)
        let imgView = makeImageView(image: image, frame: contentFrame)
        paperBackgroundView.addSubview(imgView)
        imageViews[id] = imgView
        imageLayers[id] = imgView.layer

        let needed = startY + h + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height {
            canvasView.contentSize.height = needed
            updateBackgroundFrame()
        }

        let entry = InsertedImage(id: id, filename: filename,
                                  startX: startX, startY: startY, width: w, height: h)
        document.insertedImages.append(entry)
        addImageHandle(for: imgView, at: contentFrame, id: id, isText: false)
        document.documentHeight = canvasView.contentSize.height
        store.saveDocument(document)
        showToastBanner(text: "Grafik eingefügt", icon: "photo")

        if registerUndoAction {
            registerCustomUndo(actionName: "Bild einfügen") { [weak self] in
                guard let self else { return }
                self.deleteInsertedElement(id: id, registerUndoAction: false)
                self.store.saveDocument(self.document)

                self.registerCustomUndo(actionName: "Bild einfügen") { [weak self] in
                    self?.insertImage(image, at: explicitOrigin, registerUndoAction: true)
                }
            }
        }
    }

    // MARK: - Clipboard Copy & Paste

    func pasteFromClipboard(at explicitOrigin: CGPoint? = nil) {
        let pb = UIPasteboard.general
        let origin: CGPoint
        if let explicitOrigin {
            origin = explicitOrigin
        } else {
            let sc = max(canvasView.zoomScale, 0.01)
            let off = canvasView.contentOffset
            origin = CGPoint(
                x: max(20, (off.x + canvasView.bounds.width * 0.15) / sc),
                y: max(20, (off.y + canvasView.bounds.height * 0.25) / sc)
            )
        }

        // 1. Paste image
        if let img = pb.image {
            insertImage(img, at: origin)
            showToastBanner(text: "Bild aus Zwischenablage eingefügt", icon: "photo")
            return
        }

        // 2. Paste text
        if let str = pb.string, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleanStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
            insertTypedText(text: cleanStr, fontSize: 22, contentOrigin: origin, addHandle: false)
            showToastBanner(text: "Text aus Zwischenablage eingefügt", icon: "doc.text")
            return
        }

        // 3. Paste PDF / File URL
        if let url = pb.url, url.pathExtension.lowercased() == "pdf" {
            insertPDF(from: url)
            showToastBanner(text: "PDF eingefügt", icon: "doc.richtext")
            return
        }

        showToastBanner(text: "Zwischenablage ist leer", icon: "info.circle")
    }

    func showToastBanner(text: String, icon: String) {
        let toast = UIView()
        toast.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        toast.layer.cornerRadius = 14
        toast.layer.shadowColor = UIColor.black.cgColor
        toast.layer.shadowOpacity = 0.18
        toast.layer.shadowOffset = CGSize(width: 0, height: 4)
        toast.layer.shadowRadius = 10
        toast.layer.borderWidth = 0.5
        toast.layer.borderColor = UIColor.separator.cgColor
        toast.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        toast.addSubview(stack)
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: toast.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -9),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])

        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -20)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            toast.alpha = 1
            toast.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: []) {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: -20)
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }

    func duplicateLassoSelection() {
        guard !lastLassoPoints.isEmpty || !lastScanRect.isNull else { return }
        let clearRect = lastScanRect

        let lassoPolygon = UIBezierPath()
        if let first = lastLassoPoints.first {
            lassoPolygon.move(to: first)
            for pt in lastLassoPoints.dropFirst() { lassoPolygon.addLine(to: pt) }
            lassoPolygon.close()
        }

        let selectedStrokes = canvasView.drawing.strokes.filter { stroke in
            if !lastLassoPoints.isEmpty {
                let mid = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
                return lassoPolygon.contains(mid) || clearRect.contains(stroke.renderBounds)
            } else {
                return clearRect.intersects(stroke.renderBounds)
            }
        }

        let transform = CGAffineTransform(translationX: 30, y: 30)
        let newStrokes = selectedStrokes.map { stroke -> PKStroke in
            var newStroke = stroke
            newStroke.transform = stroke.transform.concatenating(transform)
            return newStroke
        }
        canvasView.drawing.strokes.append(contentsOf: newStrokes)

        let matchingImages = document.insertedImages.filter { entry in
            let frame = CGRect(x: entry.startX, y: entry.startY, width: entry.width, height: entry.height)
            return frame.intersects(clearRect)
        }
        for entry in matchingImages {
            if let img = UIImage(contentsOfFile: store.imageURL(filename: entry.filename).path) {
                let newOrigin = CGPoint(x: entry.startX + 30, y: entry.startY + 30)
                if let text = entry.textContent {
                    insertTypedText(text: text, fontSize: entry.fontSize ?? 22, contentOrigin: newOrigin, addHandle: false)
                } else {
                    insertImage(img, at: newOrigin)
                }
            }
        }

        showToastBanner(text: "Auswahl dupliziert", icon: "doc.on.doc")
    }

    func copyLassoSelection() {
        guard !lastScanItems.isEmpty || !lastScanRect.isNull else { return }
        let combinedText = lastScanItems.map(\.copyText).joined(separator: "\n")
        if !combinedText.isEmpty {
            UIPasteboard.general.string = combinedText
        }
        if let img = compositeVisible(rect: lastScanRect, drawing: canvasView.drawing) {
            UIPasteboard.general.image = img
        }
        showToastBanner(text: "In Zwischenablage kopiert", icon: "doc.on.doc")
    }

    // MARK: - Load on open

    private func loadPDFEntry(_ entry: InsertedPDF) {
        guard let pdf = PDFDocument(url: store.pdfURL(filename: entry.filename)) else { return }
        var y = entry.startY
        let docW = max(canvasView.contentSize.width, 834)
        let pageMargin: CGFloat = 20
        let availableW = docW - pageMargin * 2

        for (i, h) in entry.pageHeights.enumerated() {
            guard let page = pdf.page(at: i) else { continue }
            let b = page.bounds(for: .cropBox)
            let pageW = min(availableW, b.width > 0 ? b.width : 595)
            let scale = pageW / max(b.width, 1)
            let pageH = h > 0 ? h : ((b.height > 0 ? b.height : 842) * scale)

            let img = renderPDFPage(page, width: pageW, height: pageH)
            if let imgFilename = try? store.saveImage(img) {
                let pageId = UUID()
                let startX: CGFloat = max(pageMargin, (docW - pageW) / 2)
                let imageEntry = InsertedImage(id: pageId, filename: imgFilename, startX: startX, startY: y, width: pageW, height: pageH)
                document.insertedImages.append(imageEntry)
                loadImageEntry(imageEntry)
            } else {
                addPDFLayer(page: page, at: y, height: pageH)
            }
            y += pageH + 24
        }
    }

    private func loadImageEntry(_ entry: InsertedImage) {
        guard let img = UIImage(contentsOfFile: store.imageURL(filename: entry.filename).path) else { return }
        let contentFrame = CGRect(x: entry.startX, y: entry.startY,
                                  width: entry.width, height: entry.height)
        let imgView = makeImageView(image: img, frame: contentFrame)
        if let rot = entry.rotation, rot != 0 {
            imgView.transform = CGAffineTransform(rotationAngle: rot)
        }
        paperBackgroundView.addSubview(imgView)
        imageViews[entry.id] = imgView
        imageLayers[entry.id] = imgView.layer
        addImageHandle(for: imgView, at: contentFrame, id: entry.id, isText: entry.textContent != nil)
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

        paperBackgroundView.addSubview(imgView)
        pdfViews.append(imgView)
        pdfLayers.append(imgView.layer)
        return h
    }

    private func renderPDFPage(_ page: PDFPage, width: CGFloat, height: CGFloat) -> UIImage {
        let scale = max(UIScreen.main.scale, 2.0)
        let targetSize = CGSize(width: max(width, 100) * scale, height: max(height, 100) * scale)
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
        showSelectionOverlay(mode: .handwriting)
    }

    func recogniseMathSelection() {
        showSelectionOverlay(mode: .math)
    }

    // MARK: - Universal Transform Box & Lasso Selection Tools (Markieren, Verschieben, Drehen, Vergrößern)

    func setCanvasToolType(_ tool: CanvasToolType) {
        currentCanvasToolType = tool
        if tool == .lasso {
            enableLassoMode()
        } else {
            disableLassoMode()
        }
    }

    private func enableLassoMode() {
        if lassoOverlay == nil {
            let overlay = LassoCanvasOverlay(frame: CGRect(origin: .zero, size: canvasView.contentSize))
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvasView.addSubview(overlay)
            lassoOverlay = overlay

            overlay.onLassoSelected = { [weak self] points, boundingBox in
                self?.handleLassoSelection(points: points, boundingBox: boundingBox)
            }
            overlay.onTapOutside = { [weak self] in
                self?.activeTransformBox?.dismiss()
            }
        }
        canvasView.drawingGestureRecognizer.isEnabled = false
    }

    private func disableLassoMode() {
        activeTransformBox?.dismiss()
        lassoOverlay?.removeFromSuperview()
        lassoOverlay = nil
        canvasView.drawingGestureRecognizer.isEnabled = true
    }

    private func handleLassoSelection(points: [CGPoint], boundingBox: CGRect) {
        activeTransformBox?.dismiss()

        // 1. Check for handwriting strokes inside the lasso
        let lassoPolygon = UIBezierPath()
        if let first = points.first {
            lassoPolygon.move(to: first)
            for pt in points.dropFirst() { lassoPolygon.addLine(to: pt) }
            lassoPolygon.close()
        }

        var selectedIndices: [Int] = []
        var selectedStrokes: [PKStroke] = []

        for (idx, stroke) in canvasView.drawing.strokes.enumerated() {
            let b = stroke.renderBounds
            let mid = CGPoint(x: b.midX, y: b.midY)
            if lassoPolygon.contains(mid) || boundingBox.contains(b) {
                selectedIndices.append(idx)
                selectedStrokes.append(stroke)
            }
        }

        if !selectedStrokes.isEmpty {
            let unionBounds = selectedStrokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
            presentTransformBox(for: selectedStrokes, indices: selectedIndices, bounds: unionBounds)
            return
        }

        // 2. Check for inserted images / text elements
        for entry in document.insertedImages {
            let entryRect = CGRect(x: entry.startX, y: entry.startY, width: entry.width, height: entry.height)
            if boundingBox.intersects(entryRect) || boundingBox.contains(entryRect) {
                presentTransformBox(forElementId: entry.id)
                return
            }
        }
    }

    private func presentTransformBox(for strokes: [PKStroke], indices: [Int], bounds: CGRect) {
        activeTransformBox?.dismiss()
        guard bounds.width > 5 && bounds.height > 5 else { return }

        let paddedBounds = bounds.insetBy(dx: -12, dy: -12)
        let center = CGPoint(x: paddedBounds.midX, y: paddedBounds.midY)
        let box = UniversalTransformBox(center: center, size: paddedBounds.size)

        box.baseStrokes = strokes
        box.strokeOriginalIndices = indices
        box.baseTransforms = strokes.map { $0.transform }

        paperBackgroundView.addSubview(box)
        activeTransformBox = box
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        box.onLiveUpdateStrokes = { [weak self, weak box] currentCenter, currentScale, currentRotation in
            guard let self = self, let box = box else { return }
            let baseCenter = box.baseCenter
            let dx = currentCenter.x - baseCenter.x
            let dy = currentCenter.y - baseCenter.y

            let t = CGAffineTransform(translationX: baseCenter.x + dx, y: baseCenter.y + dy)
                .rotated(by: currentRotation)
                .scaledBy(x: currentScale, y: currentScale)
                .translatedBy(x: -baseCenter.x, y: -baseCenter.y)

            var allStrokes = self.canvasView.drawing.strokes
            for (i, originalIdx) in box.strokeOriginalIndices.enumerated() {
                guard originalIdx < allStrokes.count else { continue }
                var s = box.baseStrokes[i]
                s.transform = box.baseTransforms[i].concatenating(t)
                allStrokes[originalIdx] = s
            }
            self.canvasView.drawing.strokes = allStrokes
        }

        box.onCommitStrokes = { [weak self] _, _, _ in
            guard let self = self else { return }
            let prevStrokes = self.canvasView.drawing.strokes
            self.store?.saveDrawing(self.canvasView.drawing)
            self.registerCustomUndo(actionName: "Handschrift transformieren") { [weak self] in
                guard let self = self else { return }
                self.canvasView.drawing.strokes = prevStrokes
                self.activeTransformBox?.dismiss()
                self.store?.saveDrawing(self.canvasView.drawing)
            }
        }

        box.onDuplicate = { [weak self, weak box] in
            guard let self = self, let box = box else { return }
            let offset = CGAffineTransform(translationX: 30, y: 30)
            var duplicatedStrokes: [PKStroke] = []
            var newIndices: [Int] = []
            let startIdx = self.canvasView.drawing.strokes.count
            for (i, s) in box.baseStrokes.enumerated() {
                var clone = s
                clone.transform = clone.transform.concatenating(offset)
                duplicatedStrokes.append(clone)
                newIndices.append(startIdx + i)
            }
            self.canvasView.drawing.strokes.append(contentsOf: duplicatedStrokes)
            self.store?.saveDrawing(self.canvasView.drawing)
            self.showToastBanner(text: "Auswahl dupliziert", icon: "doc.on.doc")
            let newBounds = duplicatedStrokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
            self.presentTransformBox(for: duplicatedStrokes, indices: newIndices, bounds: newBounds)
        }

        box.onChangeColor = { [weak self, weak box] newColor in
            guard let self = self, let box = box else { return }
            var allStrokes = self.canvasView.drawing.strokes
            for (i, originalIdx) in box.strokeOriginalIndices.enumerated() {
                guard originalIdx < allStrokes.count else { continue }
                var s = allStrokes[originalIdx]
                s.ink = PKInk(s.ink.inkType, color: newColor)
                allStrokes[originalIdx] = s
                box.baseStrokes[i].ink = PKInk(box.baseStrokes[i].ink.inkType, color: newColor)
            }
            self.canvasView.drawing.strokes = allStrokes
            self.store?.saveDrawing(self.canvasView.drawing)
        }

        box.onDelete = { [weak self, weak box] in
            guard let self = self, let box = box else { return }
            let prevStrokes = self.canvasView.drawing.strokes
            let removeIndices = Set(box.strokeOriginalIndices)
            self.canvasView.drawing.strokes = self.canvasView.drawing.strokes.enumerated().compactMap { idx, stroke in
                removeIndices.contains(idx) ? nil : stroke
            }
            self.store?.saveDrawing(self.canvasView.drawing)
            box.dismiss()
            self.showToastBanner(text: "Auswahl gelöscht", icon: "trash")
            self.registerCustomUndo(actionName: "Auswahl löschen") { [weak self] in
                guard let self = self else { return }
                self.canvasView.drawing.strokes = prevStrokes
                self.store?.saveDrawing(self.canvasView.drawing)
            }
        }

        box.onDismiss = { [weak self] in
            if self?.activeTransformBox === box {
                self?.activeTransformBox = nil
            }
        }
    }

    func presentTransformBox(forElementId id: UUID) {
        activeTransformBox?.dismiss()
        guard let entry = document.insertedImages.first(where: { $0.id == id }) else { return }
        guard let targetView = imageViews[id] else { return }

        let isText = entry.textContent != nil
        let baseSize = CGSize(width: entry.width, height: entry.height)
        let center = CGPoint(x: entry.startX + entry.width / 2, y: entry.startY + entry.height / 2)
        let rotation = entry.rotation ?? 0

        let box = UniversalTransformBox(center: center, size: baseSize, initialRotation: rotation)
        box.elementId = id
        box.targetElementView = targetView
        box.isTextElement = isText
        box.baseFontSize = entry.fontSize

        paperBackgroundView.addSubview(box)
        activeTransformBox = box
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        box.onLiveUpdateElement = { [weak box, weak self] currentCenter, currentScale, currentRotation in
            guard let box = box, let tv = box.targetElementView else { return }
            let newW = max(30, box.baseSize.width * currentScale)
            let newH = max(30, box.baseSize.height * currentScale)
            tv.bounds = CGRect(x: 0, y: 0, width: newW, height: newH)
            tv.center = currentCenter
            tv.transform = CGAffineTransform(rotationAngle: currentRotation)

            if let handle = self?.imageHandles[id] {
                handle.bounds = CGRect(x: 0, y: 0, width: newW, height: newH)
                handle.center = currentCenter
                handle.transform = CGAffineTransform(rotationAngle: currentRotation)
            }
        }

        box.onCommitElement = { [weak self, weak box] currentCenter, currentScale, currentRotation in
            guard let self = self, let box = box, let elementId = box.elementId else { return }
            guard let idx = self.document.insertedImages.firstIndex(where: { $0.id == elementId }) else { return }
            let newW = max(30, box.baseSize.width * currentScale)
            let newH = max(30, box.baseSize.height * currentScale)
            self.document.insertedImages[idx].startX = currentCenter.x - newW / 2
            self.document.insertedImages[idx].startY = currentCenter.y - newH / 2
            self.document.insertedImages[idx].width  = newW
            self.document.insertedImages[idx].height = newH
            self.document.insertedImages[idx].rotation = currentRotation

            if box.isTextElement {
                let baseFont = box.baseFontSize ?? 22
                self.document.insertedImages[idx].fontSize = max(10, min(baseFont * currentScale, 120))
            }
            self.store?.saveDocument(self.document)
        }

        box.onDuplicate = { [weak self] in
            guard let self = self else { return }
            guard let idx = self.document.insertedImages.firstIndex(where: { $0.id == id }) else { return }
            let orig = self.document.insertedImages[idx]
            let newId = UUID()
            let clone = InsertedImage(
                id: newId,
                filename: orig.filename,
                startX: orig.startX + 30,
                startY: orig.startY + 30,
                width: orig.width,
                height: orig.height,
                textContent: orig.textContent,
                fontSize: orig.fontSize,
                fontDesign: orig.fontDesign,
                fontColorHex: orig.fontColorHex,
                rotation: orig.rotation
            )
            self.document.insertedImages.append(clone)
            self.store?.saveDocument(self.document)
            if let image = self.imageViews[id]?.image {
                let imgView = self.makeImageView(image: image, frame: CGRect(x: clone.startX, y: clone.startY, width: clone.width, height: clone.height))
                imgView.transform = CGAffineTransform(rotationAngle: clone.rotation ?? 0)
                self.canvasView.addSubview(imgView)
                self.imageViews[newId] = imgView
                self.imageLayers[newId] = imgView.layer
                self.addImageHandle(for: imgView, at: CGRect(x: clone.startX, y: clone.startY, width: clone.width, height: clone.height), id: newId, isText: isText)
            }
            self.showToastBanner(text: "Element dupliziert", icon: "doc.on.doc")
            self.presentTransformBox(forElementId: newId)
        }

        box.onDelete = { [weak self] in
            guard let self = self else { return }
            self.deleteInsertedElement(id: id)
            self.activeTransformBox?.dismiss()
        }

        box.onDismiss = { [weak self] in
            if self?.activeTransformBox === box {
                self?.activeTransformBox = nil
            }
        }
    }

    // MARK: - Long Press to Move, Rotate, Scale (Gedrückt halten & Verschieben)

    func setupCanvasLongPress() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleCanvasLongPress(_:)))
        lp.minimumPressDuration = 0.32
        lp.allowableMovement = 20.0
        lp.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        lp.delegate = self
        canvasView.addGestureRecognizer(lp)
        canvasLongPress = lp
    }

    func setupCanvasTapToDeselect() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCanvasTapToDeselect(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        canvasView.addGestureRecognizer(tap)
    }

    @objc private func handleCanvasTapToDeselect(_ gr: UITapGestureRecognizer) {
        guard let box = activeTransformBox else { return }
        let rawLoc = gr.location(in: canvasView)
        let zoom = max(canvasView.zoomScale, 0.01)
        let loc = CGPoint(x: rawLoc.x / zoom, y: rawLoc.y / zoom)
        if !box.frame.insetBy(dx: -25, dy: -25).contains(loc) {
            box.dismiss()
        }
    }

    @objc private func handleCanvasLongPress(_ gr: UILongPressGestureRecognizer) {
        let rawLoc = gr.location(in: canvasView)
        let zoom = max(canvasView.zoomScale, 0.01)
        let loc = CGPoint(x: rawLoc.x / zoom, y: rawLoc.y / zoom)

        switch gr.state {
        case .began:
            if let box = activeTransformBox, box.frame.insetBy(dx: -15, dy: -15).contains(loc) {
                return
            }

            // 1. Check if an inserted element (image, text block, etc.) is under the touch
            if let elementId = findElement(near: loc) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                presentTransformBox(forElementId: elementId)
                longPressInitialTouch = loc
                longPressStartCenter = activeTransformBox?.center
                isLongPressDragging = true
                return
            }

            // 2. Check if handwriting / drawing strokes are under the touch
            if let cluster = findStrokeCluster(near: loc) {
                removeAccidentalDotStroke(near: loc)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let unionBounds = cluster.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
                presentTransformBox(for: cluster.strokes, indices: cluster.indices, bounds: unionBounds)
                longPressInitialTouch = loc
                longPressStartCenter = activeTransformBox?.center
                isLongPressDragging = true
                return
            }

        case .changed:
            guard isLongPressDragging,
                  let box = activeTransformBox,
                  let initialTouch = longPressInitialTouch,
                  let startCenter = longPressStartCenter else { return }

            let deltaX = loc.x - initialTouch.x
            let deltaY = loc.y - initialTouch.y
            box.center = CGPoint(x: startCenter.x + deltaX, y: startCenter.y + deltaY)
            box.currentCenter = box.center
            box.triggerLiveUpdate()

        case .ended, .cancelled:
            if isLongPressDragging, let box = activeTransformBox {
                box.triggerCommit()
                isLongPressDragging = false
                longPressInitialTouch = nil
                longPressStartCenter = nil
            }

        default:
            isLongPressDragging = false
            longPressInitialTouch = nil
            longPressStartCenter = nil
        }
    }

    private func findElement(near point: CGPoint) -> UUID? {
        for entry in document.insertedImages.reversed() {
            let rect = CGRect(x: entry.startX, y: entry.startY, width: entry.width, height: entry.height)
            if rect.insetBy(dx: -15, dy: -15).contains(point) {
                return entry.id
            }
        }
        return nil
    }

    private func findStrokeCluster(near point: CGPoint, maxDistance: CGFloat = 35.0) -> (indices: [Int], strokes: [PKStroke])? {
        let allStrokes = canvasView.drawing.strokes
        guard !allStrokes.isEmpty else { return nil }

        var closestIdx: Int? = nil
        var closestDist: CGFloat = maxDistance

        for (idx, stroke) in allStrokes.enumerated() {
            let b = stroke.renderBounds
            if b.insetBy(dx: -closestDist, dy: -closestDist).contains(point) {
                let dx = max(b.minX - point.x, 0, point.x - b.maxX)
                let dy = max(b.minY - point.y, 0, point.y - b.maxY)
                let dist = hypot(dx, dy)
                if dist < closestDist {
                    closestDist = dist
                    closestIdx = idx
                }
            }
        }

        guard let startIdx = closestIdx else { return nil }

        var selectedSet = Set<Int>([startIdx])
        var queue = [startIdx]
        let clusterRadius: CGFloat = 28.0

        while !queue.isEmpty {
            let curIdx = queue.removeFirst()
            let curBounds = allStrokes[curIdx].renderBounds.insetBy(dx: -clusterRadius, dy: -clusterRadius)

            for (idx, stroke) in allStrokes.enumerated() {
                if !selectedSet.contains(idx) && curBounds.intersects(stroke.renderBounds) {
                    selectedSet.insert(idx)
                    queue.append(idx)
                }
            }
        }

        let sortedIndices = selectedSet.sorted()
        let strokes = sortedIndices.map { allStrokes[$0] }
        return (sortedIndices, strokes)
    }

    private func removeAccidentalDotStroke(near point: CGPoint) {
        guard let lastStroke = canvasView.drawing.strokes.last else { return }
        let b = lastStroke.renderBounds
        if b.width < 10 && b.height < 10 && b.insetBy(dx: -16, dy: -16).contains(point) {
            canvasView.drawing.strokes.removeLast()
        }
    }

    // MARK: - Selection overlay

    private func showSelectionOverlay(mode: SelectionMode = .handwriting) {
        let overlay = HandwritingSelectionOverlay(mode: mode)
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
            Task { await self.recogniseInRegion(contentRect: contentRect, lassoPoints: contentPoints, mathMode: mode == .math) }
        }

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
    }

    @MainActor
    private func recogniseInRegion(contentRect: CGRect, lassoPoints: [CGPoint] = [], mathMode: Bool = false) async {
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

        let obs = await runVision(on: composite, mathMode: mathMode)
        spinner.removeFromSuperview()

        var items: [RecognitionBannerView.Item] = []
        for o in obs {
            guard let text = o.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let expr = leftOfEquals(text)
            if looksLikeMath(expr), case .success(let v) = evaluator.evaluate(expr) {
                let formattedResult = fmt(v)
                let cleanText = text.trimmingCharacters(in: .whitespaces)
                let fullEquation = cleanText.contains("=") ? "\(cleanText) \(formattedResult)" : "\(cleanText) = \(formattedResult)"
                items.append(.init(label: fullEquation, copyText: fullEquation))
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
                    let fullEquation = cleanText.contains("=") ? "\(cleanText) \(formattedResult)" : "\(cleanText) = \(formattedResult)"
                    items.append(.init(label: fullEquation, copyText: fullEquation))
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
        banner.onCopy = { [weak self] in
            guard let self else { return }
            self.copyLassoSelection()
            self.hideBanner()
        }
        banner.onDuplicate = { [weak self] in
            guard let self else { return }
            self.duplicateLassoSelection()
            self.hideBanner()
        }
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
        let previousDrawing = canvasView.drawing
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
        let insertedId = insertTypedText(text: combinedText, fontSize: 22, contentOrigin: origin, addHandle: true, registerUndoAction: false)

        registerCustomUndo(actionName: "Handschrift umwandeln") { [weak self] in
            guard let self else { return }
            let redoDrawing = self.canvasView.drawing
            if let insertedId {
                self.deleteInsertedElement(id: insertedId, registerUndoAction: false)
            }
            self.canvasView.drawing = previousDrawing
            self.store?.saveDrawing(previousDrawing)
            self.store?.saveDocument(self.document)

            self.registerCustomUndo(actionName: "Handschrift umwandeln") { [weak self] in
                guard let self else { return }
                self.canvasView.drawing = redoDrawing
                _ = self.insertTypedText(text: combinedText, fontSize: 22, contentOrigin: origin, addHandle: true, registerUndoAction: false)
                self.store?.saveDrawing(redoDrawing)
                self.store?.saveDocument(self.document)
            }
        }
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
            self.insertTypedText(text: text, fontSize: fontSize, contentOrigin: contentPt, addHandle: true, registerUndoAction: true)
        }

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
    }

    private func viewPointToContent(_ pt: CGPoint) -> CGPoint {
        let sc  = max(canvasView.zoomScale, 0.01)
        let off = canvasView.contentOffset
        return CGPoint(x: (pt.x + off.x) / sc, y: (pt.y + off.y) / sc)
    }

    func fontFor(design: String?, size: CGFloat) -> UIFont {
        let style = design ?? "default"
        switch style {
        case "rounded":
            if let desc = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: desc, size: size)
            }
        case "serif":
            if let desc = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: desc, size: size)
            }
        case "monospaced":
            if let desc = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(.monospaced) {
                return UIFont(descriptor: desc, size: size)
            }
        case "handwriting":
            if let font = UIFont(name: "Noteworthy-Bold", size: size) ?? UIFont(name: "ChalkboardSE-Regular", size: size) ?? UIFont(name: "SnellRoundhand", size: size) {
                return font
            }
        case "marker":
            if let font = UIFont(name: "MarkerFelt-Wide", size: size) {
                return font
            }
        default:
            break
        }
        return UIFont.systemFont(ofSize: size, weight: .regular)
    }

    @discardableResult
    func insertTypedText(text: String, fontSize: CGFloat, fontDesign: String? = nil, colorHex: String? = nil, contentOrigin: CGPoint, addHandle: Bool = true, registerUndoAction: Bool = true) -> UUID? {
        let img = renderTypedText(text, fontSize: fontSize, fontDesign: fontDesign, colorHex: colorHex, originX: contentOrigin.x)
        guard let filename = try? store.saveImage(img) else { return nil }

        let id = UUID()
        let contentFrame = CGRect(x: contentOrigin.x, y: contentOrigin.y,
                                  width: img.size.width, height: img.size.height)
        let imgView = makeImageView(image: img, frame: contentFrame)
        imgView.layer.borderWidth = 0
        imgView.layer.borderColor = nil
        imgView.backgroundColor = .clear

        paperBackgroundView.addSubview(imgView)
        imageViews[id] = imgView
        imageLayers[id] = imgView.layer

        let entry = InsertedImage(id: id, filename: filename,
                                  startX: contentOrigin.x, startY: contentOrigin.y,
                                  width: img.size.width, height: img.size.height,
                                  textContent: text, fontSize: fontSize,
                                  fontDesign: fontDesign, fontColorHex: colorHex)
        document.insertedImages.append(entry)
        if addHandle {
            addImageHandle(for: imgView, at: contentFrame, id: id, isText: true)
        }
        let needed = contentOrigin.y + img.size.height + Self.initialHeight * 0.3
        if needed > canvasView.contentSize.height { canvasView.contentSize.height = needed }
        document.documentHeight = canvasView.contentSize.height
        store.saveDocument(document)

        if registerUndoAction {
            registerCustomUndo(actionName: "Text einfügen") { [weak self] in
                guard let self else { return }
                self.deleteInsertedElement(id: id, registerUndoAction: false)
                self.store.saveDocument(self.document)

                self.registerCustomUndo(actionName: "Text einfügen") { [weak self] in
                    self?.insertTypedText(text: text, fontSize: fontSize, fontDesign: fontDesign, colorHex: colorHex, contentOrigin: contentOrigin, addHandle: addHandle, registerUndoAction: true)
                }
            }
        }
        return id
    }

    func renderTypedText(_ text: String, fontSize: CGFloat, fontDesign: String? = nil, colorHex: String? = nil, originX: CGFloat = 0) -> UIImage {
        let font = fontFor(design: fontDesign, size: fontSize)
        let textColor: UIColor
        if let hex = colorHex, let c = UIColor(hex: hex) {
            textColor = c
        } else {
            textColor = document.darkDrawingMode ? UIColor.white : UIColor.black
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str = NSAttributedString(string: text, attributes: attrs)

        let available = max(canvasView.contentSize.width - originX - 10, 100)
        let w = min(available, canvasView.contentSize.width * 0.9)
        let textH = str.boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        let totalH = max(textH + 6, fontSize + 6)

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
        let scale = canvasView.zoomScale
        paperBackgroundView.transform = CGAffineTransform(scaleX: scale, y: scale)
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
                // Render paper background layer
                paperBackgroundView.layer.render(in: pdfCtx)
                // Render image layers
                imageLayers.values.forEach { $0.render(in: pdfCtx) }
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
    var onCopy: (() -> Void)?
    var onDuplicate: (() -> Void)?
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

        let copyBtn = makeButton(title: "Kopieren", image: "doc.on.doc", tint: .systemBlue) { [weak self] in
            self?.onCopy?()
        }
        titleRow.addArrangedSubview(copyBtn)

        let dupeBtn = makeButton(title: "Duplizieren", image: "plus.square.on.square", tint: .systemTeal) { [weak self] in
            self?.onDuplicate?()
        }
        titleRow.addArrangedSubview(dupeBtn)

        let insertBtn = makeButton(title: "Als Text", image: "text.badge.plus", tint: .systemIndigo) { [weak self] in
            self?.onInsertAsText?()
        }
        titleRow.addArrangedSubview(insertBtn)

        let replaceBtn = makeButton(title: "Ersetzen", image: "pencil.slash", tint: .systemOrange) { [weak self] in
            self?.onReplaceHandwriting?()
        }
        titleRow.addArrangedSubview(replaceBtn)

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

/// An interactive UIView overlaid on an inserted image, clip-art, or typed text block.
/// Provides smooth drag-to-move, 2-finger pinch-to-scale, corner transform dots, and quick styling menus.
/// Passes Apple Pencil touches directly to PKCanvasView for uninterrupted, high-performance drawing.
final class ImageHandleView: UIView {

    /// Canvas-coordinate frame of the element.
    var contentFrame: CGRect
    var isTextElement: Bool = false

    var onMoved: ((_ newFrame: CGRect, _ oldFrame: CGRect) -> Void)?
    var onScaled: ((_ scaleMultiplier: CGFloat) -> Void)?
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onStyleMenu: (() -> Void)?

    private weak var targetView: UIView?
    private var initialDragFrame: CGRect = .zero
    var isSelected: Bool = false

    // Corner handle dots
    private let topLeftDot = UIView()
    private let topRightDot = UIView()
    private let bottomLeftDot = UIView()
    private let bottomRightDot = UIView()

    init(contentFrame: CGRect, targetView: UIView?, isText: Bool = false) {
        self.contentFrame = contentFrame
        self.targetView   = targetView
        self.isTextElement = isText
        super.init(frame: contentFrame)

        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        let touchTypes: [NSNumber] = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]

        // 1. Pan for moving (both finger and Apple Pencil)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.allowedTouchTypes = touchTypes
        addGestureRecognizer(pan)

        // 2. Pinch for scaling / resizing font (2 fingers)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinch)

        // 3. Single tap for style menu / selection (both finger and Apple Pencil)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedTouchTypes = touchTypes
        addGestureRecognizer(tap)

        // 4. Double tap for text edit (both finger and Apple Pencil)
        let dt = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        dt.numberOfTapsRequired = 2
        dt.allowedTouchTypes = touchTypes
        addGestureRecognizer(dt)
        tap.require(toFail: dt)

        // 5. Long press for style menu (both finger and Apple Pencil)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        lp.allowedTouchTypes = touchTypes
        lp.minimumPressDuration = 0.45
        addGestureRecognizer(lp)

        setupCornerDots()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupCornerDots() {
        let dots = [topLeftDot, topRightDot, bottomLeftDot, bottomRightDot]
        for dot in dots {
            dot.backgroundColor = .white
            dot.layer.borderColor = UIColor.systemBlue.cgColor
            dot.layer.borderWidth = 2.0
            dot.layer.cornerRadius = 5
            dot.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
            dot.isHidden = true
            dot.isUserInteractionEnabled = false
            addSubview(dot)
        }
        updateDotPositions()
    }

    func updateDotPositions() {
        let b = bounds
        topLeftDot.center = CGPoint(x: 0, y: 0)
        topRightDot.center = CGPoint(x: b.width, y: 0)
        bottomLeftDot.center = CGPoint(x: 0, y: b.height)
        bottomRightDot.center = CGPoint(x: b.width, y: b.height)
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        layer.borderWidth = selected ? 1.5 : 0
        layer.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.04).cgColor : UIColor.clear.cgColor
        let dots = [topLeftDot, topRightDot, bottomLeftDot, bottomRightDot]
        dots.forEach { $0.isHidden = !selected }
        updateDotPositions()
    }

    // MARK: - Gesture handlers

    @objc private func handleTap() {
        setSelected(true)
        onStyleMenu?()
    }

    @objc private func handleDoubleTap() {
        onEdit?()
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        if gr.state == .began {
            setSelected(true)
        }
        if gr.state == .changed {
            let scale = gr.scale
            gr.scale = 1.0
            onScaled?(scale)
        }
        if gr.state == .ended || gr.state == .cancelled {
            updateDotPositions()
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let delta = gr.translation(in: sv)
        gr.setTranslation(.zero, in: sv)

        if gr.state == .began {
            setSelected(true)
            initialDragFrame = contentFrame
        }

        contentFrame.origin.x += delta.x
        contentFrame.origin.y += delta.y

        frame = contentFrame
        targetView?.frame = contentFrame
        updateDotPositions()

        if gr.state == .ended || gr.state == .cancelled {
            if contentFrame != initialDragFrame {
                onMoved?(contentFrame, initialDragFrame)
            }
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        setSelected(true)
        onStyleMenu?()
    }

    // Only intercept touches when explicitly selected, allowing seamless drawing and pinch-to-zoom over elements
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isSelected, bounds.insetBy(dx: -16, dy: -12).contains(point) else { return nil }
        return self
    }
}

// MARK: - Image Handle Management & Styling

extension InfiniteNotebookViewController {

    /// Creates an interactive UIView handle over an element in the canvas.
    func addImageHandle(for targetView: UIView?, at contentFrame: CGRect, id: UUID, isText: Bool = false) {
        let handle = ImageHandleView(contentFrame: contentFrame, targetView: targetView, isText: isText)
        handle.frame = contentFrame
        canvasView.addSubview(handle)
        imageHandles[id] = handle

        handle.onStyleMenu = { [weak self] in
            guard let self else { return }
            self.presentTransformBox(forElementId: id)
        }

        handle.onEdit = { [weak self] in
            guard let self else { return }
            self.editInsertedElement(id: id)
        }

        handle.onScaled = { [weak self] scaleMultiplier in
            guard let self else { return }
            guard let idx = self.document.insertedImages.firstIndex(where: { $0.id == id }) else { return }
            let entry = self.document.insertedImages[idx]
            if entry.textContent != nil {
                let currentSize = entry.fontSize ?? 22
                let newSize = max(10, min(currentSize * scaleMultiplier, 120))
                self.updateInsertedText(id: id, fontSize: newSize)
            } else if let imgView = self.imageViews[id] {
                let newW = max(30, entry.width * scaleMultiplier)
                let newH = max(30, entry.height * scaleMultiplier)
                imgView.bounds.size = CGSize(width: newW, height: newH)
                self.document.insertedImages[idx].width = newW
                self.document.insertedImages[idx].height = newH
                self.store.saveDocument(self.document)
            }
        }

        handle.onMoved = { [weak self] newContentFrame, oldContentFrame in
            guard let self else { return }
            guard let idx = self.document.insertedImages.firstIndex(where: { $0.id == id }) else { return }
            self.document.insertedImages[idx].startX  = newContentFrame.minX
            self.document.insertedImages[idx].startY  = newContentFrame.minY
            self.document.insertedImages[idx].width   = newContentFrame.width
            self.document.insertedImages[idx].height  = newContentFrame.height
            self.store.saveDocument(self.document)

            self.registerCustomUndo(actionName: "Element verschieben") { [weak self] in
                guard let self else { return }
                guard let h = self.imageHandles[id] else { return }
                h.contentFrame = oldContentFrame
                h.frame = oldContentFrame
                self.imageViews[id]?.frame = oldContentFrame
                h.updateDotPositions()
                if let i = self.document.insertedImages.firstIndex(where: { $0.id == id }) {
                    self.document.insertedImages[i].startX = oldContentFrame.minX
                    self.document.insertedImages[i].startY = oldContentFrame.minY
                }
                self.store.saveDocument(self.document)
            }
        }

        handle.onDelete = { [weak self] in
            guard let self else { return }
            self.deleteInsertedElement(id: id)
        }
    }

    func deleteInsertedElement(id: UUID, registerUndoAction: Bool = true) {
        let existingEntry = document.insertedImages.first(where: { $0.id == id })
        let existingImage = imageViews[id]?.image

        if let imgView = imageViews.removeValue(forKey: id) {
            UIView.animate(withDuration: 0.15, animations: {
                imgView.alpha = 0
            }) { _ in
                imgView.removeFromSuperview()
            }
        }
        imageLayers.removeValue(forKey: id)?.removeFromSuperlayer()
        imageHandles.removeValue(forKey: id)?.removeFromSuperview()

        if let idx = document.insertedImages.firstIndex(where: { $0.id == id }) {
            document.insertedImages.remove(at: idx)
        }
        store?.saveDocument(document)

        if registerUndoAction, let entry = existingEntry {
            registerCustomUndo(actionName: "Löschen") { [weak self] in
                guard let self else { return }
                if let text = entry.textContent {
                    _ = self.insertTypedText(text: text, fontSize: entry.fontSize ?? 22, fontDesign: entry.fontDesign, colorHex: entry.fontColorHex, contentOrigin: CGPoint(x: entry.startX, y: entry.startY), addHandle: true, registerUndoAction: false)
                } else if let img = existingImage ?? UIImage(contentsOfFile: self.store.imageURL(filename: entry.filename).path) {
                    self.insertImage(img, at: CGPoint(x: entry.startX, y: entry.startY), registerUndoAction: false)
                }
                self.store.saveDocument(self.document)
            }
        }
    }

    func eraseInsertedElements(near point: CGPoint, radius: CGFloat = 35) {
        guard !document.insertedImages.isEmpty else { return }
        let hitRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let matchingIDs = document.insertedImages.compactMap { entry -> UUID? in
            let frame = CGRect(x: entry.startX, y: entry.startY, width: entry.width, height: entry.height)
            return frame.intersects(hitRect) ? entry.id : nil
        }
        guard !matchingIDs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for id in matchingIDs {
                self.deleteInsertedElement(id: id)
            }
        }
    }

    func editInsertedElement(id: UUID) {
        guard let entry = document.insertedImages.first(where: { $0.id == id }) else { return }

        let alert = UIAlertController(
            title: entry.textContent != nil ? "Textstil & Aktionen" : "Objekt-Aktionen",
            message: nil,
            preferredStyle: .actionSheet
        )

        if let text = entry.textContent {
            let currentSize = entry.fontSize ?? 22

            // 1. Schriftart wählen
            alert.addAction(UIAlertAction(title: "🔤 Schriftart ändern…", style: .default) { [weak self] _ in
                self?.presentFontPicker(id: id, currentDesign: entry.fontDesign)
            })

            // 2. Schriftgröße schnell anpassen
            alert.addAction(UIAlertAction(title: "➕ Schrift vergrößern (A+)", style: .default) { [weak self] _ in
                self?.updateInsertedText(id: id, fontSize: currentSize + 4)
            })
            alert.addAction(UIAlertAction(title: "➖ Schrift verkleinern (A-)", style: .default) { [weak self] _ in
                self?.updateInsertedText(id: id, fontSize: max(10, currentSize - 4))
            })
            alert.addAction(UIAlertAction(title: "🔢 Schriftgröße festlegen… (\(Int(currentSize)) pt)", style: .default) { [weak self] _ in
                self?.presentFontSizePicker(id: id, currentSize: currentSize)
            })

            // 3. Textfarbe wählen
            alert.addAction(UIAlertAction(title: "🎨 Farbe ändern…", style: .default) { [weak self] _ in
                self?.presentColorPicker(id: id)
            })

            // 4. Textinhalt bearbeiten
            alert.addAction(UIAlertAction(title: "✍️ Text bearbeiten…", style: .default) { [weak self] _ in
                self?.promptEditText(id: id, currentText: text, fontSize: currentSize)
            })

            // 5. Kopieren
            alert.addAction(UIAlertAction(title: "📋 Text kopieren", style: .default) { [weak self] _ in
                UIPasteboard.general.string = text
                self?.showToastBanner(text: "Text kopiert", icon: "doc.on.doc")
            })
        } else if let img = UIImage(contentsOfFile: store.imageURL(filename: entry.filename).path) {
            alert.addAction(UIAlertAction(title: "📋 Bild kopieren", style: .default) { [weak self] _ in
                UIPasteboard.general.image = img
                self?.showToastBanner(text: "Bild kopiert", icon: "doc.on.doc")
            })
        }

        // Duplizieren
        alert.addAction(UIAlertAction(title: "📄 Duplizieren", style: .default) { [weak self] _ in
            guard let self else { return }
            let newOrigin = CGPoint(x: entry.startX + 24, y: entry.startY + 24)
            if let text = entry.textContent {
                self.insertTypedText(text: text, fontSize: entry.fontSize ?? 22, fontDesign: entry.fontDesign, colorHex: entry.fontColorHex, contentOrigin: newOrigin)
            } else if let img = UIImage(contentsOfFile: self.store.imageURL(filename: entry.filename).path) {
                self.insertImage(img, at: newOrigin)
            }
            self.showToastBanner(text: "Dupliziert", icon: "plus.square.on.square")
        })

        // Löschen
        alert.addAction(UIAlertAction(title: "🗑 Löschen", style: .destructive) { [weak self] _ in
            self?.deleteInsertedElement(id: id)
        })
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))

        if let pop = alert.popoverPresentationController, let handle = imageHandles[id] {
            pop.sourceView = handle
            pop.sourceRect = handle.bounds
        }
        present(alert, animated: true)
    }

    private func presentFontPicker(id: UUID, currentDesign: String?) {
        let sheet = UIAlertController(title: "Schriftart wählen", message: nil, preferredStyle: .actionSheet)
        let fonts: [(name: String, key: String)] = [
            ("✍️ Handschrift (Noteworthy)", "handwriting"),
            ("📖 Klassisch (Serif)", "serif"),
            ("🟡 Rund (Rounded)", "rounded"),
            ("💻 Code / Schreibmaschine", "monospaced"),
            ("🖍 Marker (Comic)", "marker"),
            ("🅰️ Standard (San Francisco)", "default")
        ]
        for f in fonts {
            let isCurrent = (currentDesign ?? "default") == f.key
            let title = isCurrent ? "✓ " + f.name : f.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.updateInsertedText(id: id, fontDesign: f.key)
            })
        }
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        if let pop = sheet.popoverPresentationController, let handle = imageHandles[id] {
            pop.sourceView = handle
            pop.sourceRect = handle.bounds
        }
        present(sheet, animated: true)
    }

    private func presentFontSizePicker(id: UUID, currentSize: CGFloat) {
        let sheet = UIAlertController(title: "Schriftgröße wählen", message: nil, preferredStyle: .actionSheet)
        let sizes: [CGFloat] = [12, 14, 18, 22, 28, 36, 48, 64, 80]
        for s in sizes {
            let isCurrent = Int(currentSize) == Int(s)
            let title = isCurrent ? "✓ \(Int(s)) pt" : "\(Int(s)) pt"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.updateInsertedText(id: id, fontSize: s)
            })
        }
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        if let pop = sheet.popoverPresentationController, let handle = imageHandles[id] {
            pop.sourceView = handle
            pop.sourceRect = handle.bounds
        }
        present(sheet, animated: true)
    }

    private func presentColorPicker(id: UUID) {
        let sheet = UIAlertController(title: "Schriftfarbe wählen", message: nil, preferredStyle: .actionSheet)
        let colors: [(name: String, hex: String?)] = [
            ("⬛️/⬜️ Standard (Schwarz/Weiß)", nil),
            ("🔵 Blau", "#007AFF"),
            ("🔴 Rot", "#FF3B30"),
            ("🟢 Grün", "#34C759"),
            ("🟠 Orange", "#FF9500"),
            ("🟣 Lila / Violett", "#AF52DE"),
            ("🟡 Gelb", "#FFCC00"),
            ("🔘 Grau", "#8E8E93")
        ]
        for c in colors {
            sheet.addAction(UIAlertAction(title: c.name, style: .default) { [weak self] _ in
                self?.updateInsertedText(id: id, colorHex: c.hex)
            })
        }
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        if let pop = sheet.popoverPresentationController, let handle = imageHandles[id] {
            pop.sourceView = handle
            pop.sourceRect = handle.bounds
        }
        present(sheet, animated: true)
    }

    private func promptEditText(id: UUID, currentText: String, fontSize: CGFloat) {
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
            self.updateInsertedText(id: id, newText: newText, fontSize: fontSize)
        })
        present(alert, animated: true)
    }

    func updateInsertedText(id: UUID, newText: String? = nil, fontSize: CGFloat? = nil, fontDesign: String? = nil, colorHex: String? = nil, registerUndoAction: Bool = true) {
        guard let idx = document.insertedImages.firstIndex(where: { $0.id == id }) else { return }
        var entry = document.insertedImages[idx]
        guard let text = newText ?? entry.textContent else { return }

        let oldText = entry.textContent
        let oldSize = entry.fontSize ?? 22
        let oldDesign = entry.fontDesign
        let oldColor = entry.fontColorHex

        let currentSize = max(10, min(fontSize ?? oldSize, 120))
        let currentDesign = fontDesign ?? oldDesign
        let currentColor = colorHex ?? oldColor

        let newImg = renderTypedText(text, fontSize: currentSize, fontDesign: currentDesign, colorHex: currentColor, originX: entry.startX)
        guard let newFilename = try? store.saveImage(newImg) else { return }

        try? FileManager.default.removeItem(at: store.imageURL(filename: entry.filename))

        let newFrame = CGRect(x: entry.startX, y: entry.startY, width: newImg.size.width, height: newImg.size.height)
        if let imgView = imageViews[id] {
            imgView.image = newImg
            imgView.frame = newFrame
        }
        if let layer = imageLayers[id] {
            layer.contents = newImg.cgImage
            layer.frame = newFrame
        }
        if let handle = imageHandles[id] {
            handle.frame = newFrame
            handle.contentFrame = newFrame
            handle.updateDotPositions()
        }

        entry.filename = newFilename
        entry.textContent = text
        entry.fontSize = currentSize
        entry.fontDesign = currentDesign
        entry.fontColorHex = currentColor
        entry.width = newImg.size.width
        entry.height = newImg.size.height
        document.insertedImages[idx] = entry

        store.saveDocument(document)

        if registerUndoAction {
            registerCustomUndo(actionName: "Textstil anpassen") { [weak self] in
                self?.updateInsertedText(id: id, newText: oldText, fontSize: oldSize, fontDesign: oldDesign, colorHex: oldColor, registerUndoAction: false)
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension InfiniteNotebookViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === canvasLongPress {
            // Never trigger canvas long press during 2-finger pinch or scroll gestures
            if gestureRecognizer.numberOfTouches > 1 {
                return false
            }
            if let pinch = canvasView.pinchGestureRecognizer, pinch.state == .began || pinch.state == .changed {
                return false
            }
        }
        return true
    }
}

// MARK: - UIColor Hex Helper

extension UIColor {
    convenience init?(hex: String) {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.remove(at: cString.startIndex) }
        guard cString.count == 6 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - PaperBackgroundContainerView
// Container view that transparently forwards background touches to the PKCanvasView
// so that drawing and scrolling are never blocked, while nested interactive subviews
// (UniversalTransformBox, buttons) receive user touches.
final class PaperBackgroundContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self {
            return nil
        }
        return hit
    }
}
