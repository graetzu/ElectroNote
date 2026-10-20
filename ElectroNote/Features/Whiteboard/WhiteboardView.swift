import SwiftUI
import PencilKit
import UIKit

// MARK: - Whiteboard ViewController

final class WhiteboardViewController: UIViewController, PKCanvasViewDelegate {

    let canvasView = PKCanvasView()
    private var backgroundStyle: BackgroundStyle = .blank
    private var darkDrawingMode: Bool = false

    var shapeSnapEnabled: Bool = false
    private var shapeSnapTask: Task<Void, Never>?
    private var isSnappingShape: Bool = false
    private var pendingDrawAndHoldSnap: Bool = false
    private let drawAndHoldRecognizer = DrawAndHoldGestureRecognizer(target: nil, action: nil)

    private var stickyNoteViews: [UUID: StickyNoteView] = [:]

    // MARK: - Live Collaboration State
    var isApplyingRemoteStroke = false
    var lastCollabStrokeCount: Int = 0
    private var remoteCursorViews: [String: RemoteCursorBadgeView] = [:]

    var folderURL: URL? = nil {
        didSet {
            loadSavedDrawing()
        }
    }

    private var saveTask: Task<Void, Never>?

    private func loadSavedDrawing() {
        guard let folderURL = folderURL else { return }
        let pkURL = folderURL.appendingPathComponent("drawing.pkdrawing")
        let jsonURL = folderURL.appendingPathComponent("drawing.json")

        let pkExists = FileManager.default.fileExists(atPath: pkURL.path)
        let jsonExists = FileManager.default.fileExists(atPath: jsonURL.path)

        if jsonExists {
            let jsonDate = (try? jsonURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let pkDate = (try? pkURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

            if !pkExists || jsonDate > pkDate.addingTimeInterval(1.0) {
                if let drawing = PencilKitBridge.loadDrawing(from: jsonURL) {
                    canvasView.drawing = drawing
                    lastCollabStrokeCount = drawing.strokes.count
                    try? drawing.dataRepresentation().write(to: pkURL, options: .atomic)
                    return
                }
            }
        }

        if let data = try? Data(contentsOf: pkURL), let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
            lastCollabStrokeCount = drawing.strokes.count
        }
    }

    func saveDrawing() {
        guard let folderURL = folderURL else { return }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let pkURL = folderURL.appendingPathComponent("drawing.pkdrawing")
        let jsonURL = folderURL.appendingPathComponent("drawing.json")
        try? canvasView.drawing.dataRepresentation().write(to: pkURL, options: .atomic)
        PencilKitBridge.saveDrawing(canvasView.drawing, to: jsonURL)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self = self else { return }
            await MainActor.run { self.saveDrawing() }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let style: UIUserInterfaceStyle = darkDrawingMode ? .dark : .light
        overrideUserInterfaceStyle = style
        view.overrideUserInterfaceStyle = style
        view.backgroundColor = darkDrawingMode ? UIColor(white: 0.12, alpha: 1) : .white
        setupCanvas()
        loadSavedDrawing()
        setupLiveCollabHooks()
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
        let style: UIUserInterfaceStyle = darkDrawingMode ? .dark : .light
        overrideUserInterfaceStyle = style
        view.overrideUserInterfaceStyle = style
        canvasView.overrideUserInterfaceStyle = style

        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.backgroundColor = darkDrawingMode ? UIColor(white: 0.12, alpha: 1) : .white
        canvasView.drawingPolicy = .anyInput  // pencil + finger drawing
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.contentSize = CGSize(width: 3000, height: 3000)
        canvasView.isScrollEnabled = true
        canvasView.delegate = self
        view.addSubview(canvasView)

        // Default tool: Pen
        let initialColor: UIColor = darkDrawingMode ? .white : .black
        canvasView.tool = PKInkingTool(.pen, color: initialColor, width: 3)

        drawAndHoldRecognizer.attach(to: canvasView) { [weak self] in
            self?.handleDrawAndHoldTriggered()
        }
    }

    // MARK: - Shape Snapping

    private func handleDrawAndHoldTriggered() {
        guard canvasView.drawingGestureRecognizer.isEnabled,
              canvasView.tool is PKInkingTool else { return }

        pendingDrawAndHoldSnap = true
        canvasView.drawingGestureRecognizer.isEnabled = false
        canvasView.drawingGestureRecognizer.isEnabled = true

        scheduleShapeSnap(delayMs: 35)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        scheduleSave()
        if !isApplyingRemoteStroke {
            let currentCount = canvasView.drawing.strokes.count
            let myTitle = self.folderURL?.deletingPathExtension().lastPathComponent ?? LiveCollabSessionManager.shared.activeDocumentTitle
            if currentCount > lastCollabStrokeCount {
                let newStrokes = Array(canvasView.drawing.strokes.suffix(currentCount - lastCollabStrokeCount))
                for stroke in newStrokes {
                    let portable = PencilKitBridge.portableStrokes(from: PKDrawing(strokes: [stroke])).first ?? PortableStrokeDTO(color: -16777216, width: 2.0, points: [])
                    let pkStrokeBase64 = PKDrawing(strokes: [stroke]).dataRepresentation().base64EncodedString()
                    LiveCollabSessionManager.shared.sendStroke(portable, pkStrokeBase64: pkStrokeBase64, documentTitle: myTitle)
                }
            } else if currentCount == 0 && lastCollabStrokeCount > 0 {
                LiveCollabSessionManager.shared.sendStrokesCleared(documentTitle: myTitle)
            } else if currentCount < lastCollabStrokeCount {
                let portable = PencilKitBridge.portableStrokes(from: canvasView.drawing)
                let pkDrawingBase64 = canvasView.drawing.dataRepresentation().base64EncodedString()
                LiveCollabSessionManager.shared.sendFullDrawingSync(pkDrawingBase64: pkDrawingBase64, portableStrokes: portable, documentTitle: myTitle)
            }
            lastCollabStrokeCount = currentCount
        }
        guard !isSnappingShape else { return }
        scheduleShapeSnap()
    }

    private func scheduleShapeSnap(delayMs: Int = 90) {
        shapeSnapTask?.cancel()
        shapeSnapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled, let self else { return }
            self.performShapeSnap()
        }
    }

    @MainActor
    private func performShapeSnap() {
        let wasHoldTriggered = pendingDrawAndHoldSnap
        pendingDrawAndHoldSnap = false

        let strokes = canvasView.drawing.strokes
        guard let last = strokes.last else { return }

        let heldAtEnd = wasHoldTriggered || ShapeSnapper.didHoldAtEnd(of: last)
        guard shapeSnapEnabled || heldAtEnd else { return }

        guard let (snapped, _) = ShapeSnapper.snap(last, isHoldTriggered: true) else { return }

        let previousDrawing = canvasView.drawing
        isSnappingShape = true
        var updated = strokes
        updated[updated.count - 1] = snapped
        canvasView.drawing = PKDrawing(strokes: updated)
        isSnappingShape = false

        canvasView.undoManager?.registerUndo(withTarget: self) { target in
            target.isSnappingShape = true
            target.canvasView.drawing = previousDrawing
            target.isSnappingShape = false
            target.scheduleSave()
        }

        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        scheduleSave()
    }

    // MARK: - Sticky Notes

    func addStickyNote() {
        let offset = canvasView.contentOffset
        let scale = max(canvasView.zoomScale, 0.01)
        let cx = (offset.x + canvasView.bounds.width / 2) / scale - StickyNoteView.noteSize.width / 2
        let cy = (offset.y + canvasView.bounds.height / 2) / scale - StickyNoteView.noteSize.height / 2
        let note = StickyNote(id: UUID(), text: "", x: max(20, cx), y: max(20, cy), colorIndex: stickyNoteViews.count % 4)
        mountStickyNoteView(note)
        if let data = try? JSONEncoder().encode(note),
           let json = String(data: data, encoding: .utf8) {
            LiveCollabSessionManager.shared.sendStickyNoteUpsert(noteJson: json, noteId: note.id.uuidString)
        }
    }

    private func mountStickyNoteView(_ note: StickyNote) {
        let v = StickyNoteView(note: note)
        v.frame = CGRect(x: note.x, y: note.y,
                         width: StickyNoteView.noteSize.width,
                         height: StickyNoteView.noteSize.height)
        canvasView.addSubview(v)
        stickyNoteViews[note.id] = v
        v.onMoved = { [weak self] contentOrigin in
            var updated = note
            updated.x = contentOrigin.x
            updated.y = contentOrigin.y
            if let data = try? JSONEncoder().encode(updated),
               let json = String(data: data, encoding: .utf8) {
                LiveCollabSessionManager.shared.sendStickyNoteUpsert(noteJson: json, noteId: note.id.uuidString)
            }
        }
        v.onTextChanged = { [weak self] text in
            var updated = note
            updated.text = text
            if let data = try? JSONEncoder().encode(updated),
               let json = String(data: data, encoding: .utf8) {
                LiveCollabSessionManager.shared.sendStickyNoteUpsert(noteJson: json, noteId: note.id.uuidString)
            }
        }
        v.onDelete = { [weak self, weak v] in
            v?.removeFromSuperview()
            self?.stickyNoteViews.removeValue(forKey: note.id)
            LiveCollabSessionManager.shared.sendStickyNoteDeleted(noteId: note.id.uuidString)
        }
    }

    func refreshBackground(style: BackgroundStyle, dark: Bool) {
        self.backgroundStyle = style
        self.darkDrawingMode = dark

        let targetStyle: UIUserInterfaceStyle = dark ? .dark : .light
        if overrideUserInterfaceStyle != targetStyle {
            overrideUserInterfaceStyle = targetStyle
        }
        if view.overrideUserInterfaceStyle != targetStyle {
            view.overrideUserInterfaceStyle = targetStyle
        }
        if canvasView.overrideUserInterfaceStyle != targetStyle {
            canvasView.overrideUserInterfaceStyle = targetStyle
        }

        let bg = dark ? UIColor(white: 0.16, alpha: 1) : UIColor.white
        let line = dark ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1.0)
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
            let s = CGSize(width: 20, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.withAlphaComponent(0.6).setStroke()
                ctx.cgContext.setLineWidth(0.5)
                ctx.cgContext.move(to: CGPoint(x: 0, y: sp - 0.5))
                ctx.cgContext.addLine(to: CGPoint(x: 20, y: sp - 0.5))
                ctx.cgContext.strokePath()
            }
        case .grid:
            let s = CGSize(width: sp, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setStroke()
                ctx.cgContext.setLineWidth(0.5)
                ctx.cgContext.move(to: CGPoint(x: sp, y: 0)); ctx.cgContext.addLine(to: CGPoint(x: sp, y: sp))
                ctx.cgContext.move(to: CGPoint(x: 0, y: sp)); ctx.cgContext.addLine(to: CGPoint(x: sp, y: sp))
                ctx.cgContext.strokePath()
            }
        case .dotted:
            let s = CGSize(width: sp, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.setFill()
                ctx.cgContext.addEllipse(in: CGRect(x: sp - 1.5, y: sp - 1.5, width: 2.5, height: 2.5))
                ctx.cgContext.fillPath()
            }
        case .cornell:
            let s = CGSize(width: 20, height: sp)
            return UIGraphicsImageRenderer(size: s).image { ctx in
                bg.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
                line.withAlphaComponent(0.6).setStroke()
                ctx.cgContext.setLineWidth(0.5)
                ctx.cgContext.move(to: CGPoint(x: 0, y: sp - 0.5))
                ctx.cgContext.addLine(to: CGPoint(x: 20, y: sp - 0.5))
                ctx.cgContext.strokePath()
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
            for (_, v) in self?.stickyNoteViews ?? [:] {
                v.removeFromSuperview()
            }
            self?.stickyNoteViews.removeAll()
            let myTitle = self?.folderURL?.deletingPathExtension().lastPathComponent ?? LiveCollabSessionManager.shared.activeDocumentTitle
            LiveCollabSessionManager.shared.sendStrokesCleared(documentTitle: myTitle)
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

        var contentRect = bounds
        for (_, v) in stickyNoteViews {
            contentRect = contentRect.isNull ? v.frame : contentRect.union(v.frame)
        }

        let targetRect: CGRect
        if !contentRect.isNull && contentRect.width > 5 && contentRect.height > 5 {
            let padding: CGFloat = 24
            targetRect = CGRect(
                x: max(0, contentRect.minX - padding),
                y: max(0, contentRect.minY - padding),
                width: contentRect.width + padding * 2,
                height: contentRect.height + padding * 2
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
                let bg = darkDrawingMode ? UIColor(white: 0.16, alpha: 1) : UIColor.white
                let line = darkDrawingMode ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1.0)
                let pattern = makePattern(backgroundStyle, bg: bg, line: line)
                pattern.draw(in: CGRect(origin: .zero, size: renderSize))
            } else {
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: renderSize))
            }

            // Render sticky notes onto image
            for (_, v) in stickyNoteViews {
                let noteFrame = CGRect(
                    x: v.frame.minX - targetRect.minX,
                    y: v.frame.minY - targetRect.minY,
                    width: v.frame.width,
                    height: v.frame.height
                )
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: noteFrame.minX, y: noteFrame.minY)
                v.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }

            if inkImage.size.width > 0 && inkImage.size.height > 0 {
                inkImage.draw(in: CGRect(origin: .zero, size: renderSize))
            }
        }
    }

    func setupLiveCollabHooks() {
        let collab = LiveCollabSessionManager.shared

        collab.onProvideSnapshot = { [weak self] in
            guard let self = self else { return (nil, nil, nil, nil, nil) }
            let strokes = PencilKitBridge.portableStrokes(from: self.canvasView.drawing)
            let drawingData = try? JSONEncoder().encode(strokes)
            let drawingJson = drawingData.flatMap { String(data: $0, encoding: .utf8) }
            let pkDrawingBase64 = self.canvasView.drawing.dataRepresentation().base64EncodedString()
            let docTitle = self.folderURL?.deletingPathExtension().lastPathComponent ?? collab.activeDocumentTitle
            return (nil, drawingJson, pkDrawingBase64, docTitle, nil)
        }

        collab.onApplySnapshot = { [weak self] _, drawingJson, pkDrawingData, _ in
            guard let self = self else { return }
            self.isApplyingRemoteStroke = true
            if let pkDrawingData = pkDrawingData,
               let data = Data(base64Encoded: pkDrawingData),
               let nativeDrawing = try? PKDrawing(data: data) {
                self.canvasView.drawing = nativeDrawing
                self.lastCollabStrokeCount = nativeDrawing.strokes.count
            } else if let drawingJson = drawingJson,
               let data = drawingJson.data(using: .utf8),
               let strokes = try? JSONDecoder().decode([PortableStrokeDTO].self, from: data) {
                let drawing = PencilKitBridge.drawing(fromPortableStrokes: strokes)
                self.canvasView.drawing = drawing
                self.lastCollabStrokeCount = drawing.strokes.count
            }
            self.isApplyingRemoteStroke = false
        }

        collab.onRemoteStrokeReceived = { [weak self] strokeDTO, pkStrokeData, docTitle in
            guard let self = self else { return }
            let myTitle = self.folderURL?.deletingPathExtension().lastPathComponent ?? ""
            if let docTitle = docTitle, !docTitle.isEmpty, !myTitle.isEmpty, !LiveCollabSessionManager.titlesMatch(docTitle, myTitle) {
                print("[WhiteboardView] Skipping stroke intended for '\(docTitle)' while current is '\(myTitle)'")
                return
            }
            self.isApplyingRemoteStroke = true
            if let pkStrokeData = pkStrokeData,
               let data = Data(base64Encoded: pkStrokeData),
               let remoteDrawing = try? PKDrawing(data: data),
               !remoteDrawing.strokes.isEmpty {
                var current = self.canvasView.drawing
                current.strokes.append(contentsOf: remoteDrawing.strokes)
                self.canvasView.drawing = current
                self.lastCollabStrokeCount = self.canvasView.drawing.strokes.count
            } else {
                let pkDrawing = PencilKitBridge.drawing(fromPortableStrokes: [strokeDTO])
                var current = self.canvasView.drawing
                current.strokes.append(contentsOf: pkDrawing.strokes)
                self.canvasView.drawing = current
                self.lastCollabStrokeCount = self.canvasView.drawing.strokes.count
            }
            self.isApplyingRemoteStroke = false
        }

        collab.onRemoteStrokesCleared = { [weak self] docTitle in
            guard let self = self else { return }
            let myTitle = self.folderURL?.deletingPathExtension().lastPathComponent ?? ""
            if let docTitle = docTitle, !docTitle.isEmpty, !myTitle.isEmpty, !LiveCollabSessionManager.titlesMatch(docTitle, myTitle) { return }
            self.isApplyingRemoteStroke = true
            self.canvasView.drawing = PKDrawing()
            for (_, v) in self.stickyNoteViews {
                v.removeFromSuperview()
            }
            self.stickyNoteViews.removeAll()
            self.lastCollabStrokeCount = 0
            self.isApplyingRemoteStroke = false
        }

        collab.onRemoteStickyNoteUpsert = { [weak self] noteJson in
            guard let self = self,
                  let data = noteJson.data(using: .utf8),
                  let note = try? JSONDecoder().decode(StickyNote.self, from: data) else { return }
            if let existing = self.stickyNoteViews[note.id] {
                existing.update(text: note.text, origin: CGPoint(x: note.x, y: note.y))
            } else {
                self.mountStickyNoteView(note)
            }
        }

        collab.onRemoteStickyNoteDeleted = { [weak self] noteId in
            guard let self = self, let uuid = UUID(uuidString: noteId) else { return }
            self.stickyNoteViews[uuid]?.removeFromSuperview()
            self.stickyNoteViews.removeValue(forKey: uuid)
        }

        collab.onRemoteCursorMoved = { [weak self] cursor in
            guard let self = self else { return }
            let badge = self.remoteCursorViews[cursor.name] ?? {
                let b = RemoteCursorBadgeView(name: cursor.name, colorHex: cursor.colorHex)
                self.canvasView.addSubview(b)
                self.remoteCursorViews[cursor.name] = b
                return b
            }()
            badge.updatePosition(CGPoint(x: cursor.x, y: cursor.y))
        }

        if case .connected = collab.sessionState {
            collab.requestSnapshot()
        }
    }
}

// MARK: - Whiteboard Representable

struct WhiteboardRepresentable: UIViewControllerRepresentable {
    @Binding var vcRef: WhiteboardViewController?
    var folderURL: URL? = nil
    let background: BackgroundStyle
    let darkDrawingMode: Bool
    let rulerActive: Bool
    let shapeSnapEnabled: Bool

    func makeUIViewController(context: Context) -> WhiteboardViewController {
        let vc = WhiteboardViewController()
        vc.folderURL = folderURL
        vc.shapeSnapEnabled = shapeSnapEnabled
        vc.refreshBackground(style: background, dark: darkDrawingMode)
        let initialColor: Color = darkDrawingMode ? .white : .black
        let initialTool = makePKTool(tool: .pen, color: initialColor, width: 3.0, eraserType: .vector, darkDrawingMode: darkDrawingMode)
        vc.canvasView.tool = initialTool
        DispatchQueue.main.async { vcRef = vc }
        return vc
    }

    func updateUIViewController(_ vc: WhiteboardViewController, context: Context) {
        if vc.folderURL != folderURL {
            vc.folderURL = folderURL
        }
        vc.refreshBackground(style: background, dark: darkDrawingMode)
        if vc.canvasView.isRulerActive != rulerActive {
            vc.canvasView.isRulerActive = rulerActive
        }
        if vc.shapeSnapEnabled != shapeSnapEnabled {
            vc.shapeSnapEnabled = shapeSnapEnabled
        }
    }
}

// MARK: - Whiteboard SwiftUI View

struct WhiteboardView: View {
    var item: DocumentItem? = nil
    var onInsert: ((UIImage) -> Void)? = nil

    @State private var scratchItem: DocumentItem = {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddedWhiteboard_\(UUID().uuidString).ewb", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        return DocumentItem(id: UUID(), name: "Whiteboard", path: scratchDir, type: .whiteboard, modifiedAt: Date(), syncStatus: .local)
    }()

    var body: some View {
        if let item {
            InfiniteNotebookHostView(item: item, isWhiteboardMode: true)
        } else {
            NavigationStack {
                InfiniteNotebookHostView(item: scratchItem, isWhiteboardMode: true, onInsert: onInsert)
            }
        }
    }
}
