import UIKit
import PencilKit

// MARK: - Selection Mode (for OCR / Math Recognition)

enum SelectionMode {
    case handwriting
    case math

    var title: String {
        switch self {
        case .handwriting: return "Handschrift mit dem Lasso umkreisen"
        case .math:        return "Mathe-Formel mit dem Lasso umkreisen"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .handwriting: return .systemBlue
        case .math:        return .systemPurple
        }
    }
}

// MARK: - Legacy OCR / Math Recognition Selection Overlay

final class HandwritingSelectionOverlay: UIView {

    var onLassoSelected: (([CGPoint], CGRect) -> Void)?
    var onCancel: (() -> Void)?

    let mode: SelectionMode
    private var lassoPoints: [CGPoint] = []

    private lazy var hintLabel: UILabel = {
        let l = UILabel()
        l.text = mode.title
        l.textAlignment  = .center
        l.textColor      = .white
        l.font           = .systemFont(ofSize: 15, weight: .semibold)
        l.backgroundColor = mode.tintColor.withAlphaComponent(0.90)
        l.layer.cornerRadius = 14
        l.clipsToBounds  = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title             = "Abbrechen"
        cfg.baseBackgroundColor = UIColor.secondarySystemFill
        cfg.baseForegroundColor = .label
        cfg.cornerStyle       = .medium
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    init(mode: SelectionMode = .handwriting) {
        self.mode = mode
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear

        addSubview(hintLabel)
        addSubview(cancelButton)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.heightAnchor.constraint(equalToConstant: 40),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            cancelButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let loc = gr.location(in: self)
        switch gr.state {
        case .began:
            lassoPoints = [loc]
            setNeedsDisplay()
        case .changed:
            lassoPoints.append(loc)
            setNeedsDisplay()
        case .ended:
            if lassoPoints.count > 4 {
                let box = computeBoundingBox(of: lassoPoints)
                if box.width > 15 && box.height > 15 {
                    onLassoSelected?(lassoPoints, box)
                    return
                }
            }
            lassoPoints.removeAll()
            setNeedsDisplay()
        default:
            lassoPoints.removeAll()
            setNeedsDisplay()
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    private func computeBoundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .null }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    override func draw(_ rect: CGRect) {
        guard lassoPoints.count > 1 else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let path = UIBezierPath()
        path.move(to: lassoPoints[0])
        for p in lassoPoints.dropFirst() {
            path.addLine(to: p)
        }
        path.close()

        let outer = UIBezierPath(rect: bounds)
        outer.append(path.reversing())
        UIColor.black.withAlphaComponent(0.25).setFill()
        outer.fill()

        mode.tintColor.withAlphaComponent(0.12).setFill()
        path.fill()

        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setStrokeColor(mode.tintColor.cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        if let first = lassoPoints.first {
            mode.tintColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)).fill()
        }
    }
}

// MARK: - Lasso Canvas Overlay (Freihand-Auswahl für Notizen)

final class LassoCanvasOverlay: UIView {

    var onLassoSelected: (([CGPoint], CGRect) -> Void)?
    var onTapOutside: (() -> Void)?

    private var lassoPoints: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        addGestureRecognizer(tap)
        pan.require(toFail: tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        onTapOutside?()
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let loc = gr.location(in: self)
        switch gr.state {
        case .began:
            lassoPoints = [loc]
            setNeedsDisplay()
        case .changed:
            lassoPoints.append(loc)
            setNeedsDisplay()
        case .ended:
            if lassoPoints.count > 4 {
                let box = computeBoundingBox(of: lassoPoints)
                if box.width > 12 && box.height > 12 {
                    let pts = lassoPoints
                    lassoPoints.removeAll()
                    setNeedsDisplay()
                    onLassoSelected?(pts, box)
                    return
                }
            }
            lassoPoints.removeAll()
            setNeedsDisplay()
        default:
            lassoPoints.removeAll()
            setNeedsDisplay()
        }
    }

    private func computeBoundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .null }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    override func draw(_ rect: CGRect) {
        guard lassoPoints.count > 1 else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let path = UIBezierPath()
        path.move(to: lassoPoints[0])
        for p in lassoPoints.dropFirst() {
            path.addLine(to: p)
        }

        // Subtle glowing animated lasso stroke
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        if let first = lassoPoints.first {
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)).fill()
        }
    }
}

// MARK: - Corner Handle View (44x44 Touch Target)

final class CornerHandleView: UIView {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    let corner: Corner
    private let visualDot = UIView()

    init(corner: Corner) {
        self.corner = corner
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        backgroundColor = .clear
        isUserInteractionEnabled = true

        visualDot.frame = CGRect(x: 13, y: 13, width: 18, height: 18)
        visualDot.backgroundColor = .white
        visualDot.layer.borderColor = UIColor.systemBlue.cgColor
        visualDot.layer.borderWidth = 3.0
        visualDot.layer.cornerRadius = 9
        visualDot.layer.shadowColor = UIColor.black.cgColor
        visualDot.layer.shadowOpacity = 0.3
        visualDot.layer.shadowRadius = 4
        visualDot.layer.shadowOffset = CGSize(width: 0, height: 2)
        visualDot.isUserInteractionEnabled = false
        addSubview(visualDot)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -16, dy: -16).contains(point)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Rotation Handle View (50x50 Touch Target with Rotate Icon)

final class RotationHandleView: UIView {
    private let visualCircle = UIView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        backgroundColor = .clear
        isUserInteractionEnabled = true

        visualCircle.frame = CGRect(x: 12, y: 12, width: 26, height: 26)
        visualCircle.backgroundColor = .white
        visualCircle.layer.borderColor = UIColor.systemBlue.cgColor
        visualCircle.layer.borderWidth = 2.0
        visualCircle.layer.cornerRadius = 13
        visualCircle.layer.shadowColor = UIColor.black.cgColor
        visualCircle.layer.shadowOpacity = 0.25
        visualCircle.layer.shadowRadius = 3.5
        visualCircle.layer.shadowOffset = CGSize(width: 0, height: 2)
        visualCircle.isUserInteractionEnabled = false
        addSubview(visualCircle)

        let icon = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
        icon.tintColor = .systemBlue
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 5, y: 5, width: 16, height: 16)
        visualCircle.addSubview(icon)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -16, dy: -16).contains(point)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Universal Transform Box (Markieren, Verschieben, Drehen, Vergrößern)

final class UniversalTransformBox: UIView, UIGestureRecognizerDelegate {

    // Base geometry
    let baseCenter: CGPoint
    let baseSize: CGSize

    var currentCenter: CGPoint
    var currentScale: CGFloat = 1.0
    var currentRotation: CGFloat = 0.0

    // Stroke selection context (if strokes are selected)
    var isHandwriting: Bool = false {
        didSet {
            buildActionToolbar()
            updateLayout()
        }
    }
    var baseStrokes: [PKStroke] = [] {
        didSet {
            isHandwriting = !baseStrokes.isEmpty
        }
    }
    var strokeOriginalIndices: [Int] = []
    var baseTransforms: [CGAffineTransform] = []

    // Element selection context (if image or text element is selected)
    var elementId: UUID?
    weak var targetElementView: UIView?
    var isTextElement: Bool = false
    var baseFontSize: CGFloat?

    // Gesture tracking state
    var movePan: UIPanGestureRecognizer?
    var pinch: UIPinchGestureRecognizer?
    var rotate: UIRotationGestureRecognizer?
    private var initialCornerDistance: CGFloat = 100
    private var initialScaleOnCornerPan: CGFloat = 1.0
    private var initialPinchCenter: CGPoint = .zero
    private var initialBoxCenterOnPinch: CGPoint = .zero

    // Callbacks
    var onLiveUpdateStrokes: ((_ center: CGPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void)?
    var onCommitStrokes: ((_ center: CGPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void)?

    var onLiveUpdateElement: ((_ center: CGPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void)?
    var onCommitElement: ((_ center: CGPoint, _ scale: CGFloat, _ rotation: CGFloat) -> Void)?

    var onDuplicate: (() -> Void)?
    var onChangeColor: ((UIColor) -> Void)?
    var onDelete: (() -> Void)?
    var onDismiss: (() -> Void)?

    // Subviews
    private let contentBorderView = UIView()
    private let rotationStemView = UIView()
    private let rotationHandle = RotationHandleView()

    private let topLeftHandle     = CornerHandleView(corner: .topLeft)
    private let topRightHandle    = CornerHandleView(corner: .topRight)
    private let bottomLeftHandle  = CornerHandleView(corner: .bottomLeft)
    private let bottomRightHandle = CornerHandleView(corner: .bottomRight)

    // Badges & Toolbars
    private let badgeView = UIView()
    private let badgeLabel = UILabel()

    private let actionToolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let colorPaletteBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))

    // MARK: - Initializer

    init(center: CGPoint, size: CGSize, initialRotation: CGFloat = 0.0) {
        self.baseCenter = center
        self.baseSize   = CGSize(width: max(32, size.width), height: max(32, size.height))
        self.currentCenter = center
        self.currentRotation = initialRotation
        super.init(frame: CGRect(x: 0, y: 0, width: baseSize.width, height: baseSize.height))

        self.center = currentCenter
        self.transform = CGAffineTransform(rotationAngle: currentRotation)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        setupViews()
        setupGestures()
        updateLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup Views

    private func setupViews() {
        // Border & Tint
        contentBorderView.layer.borderColor = UIColor.systemBlue.cgColor
        contentBorderView.layer.borderWidth = 1.5
        contentBorderView.layer.cornerRadius = 6
        contentBorderView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.06)
        contentBorderView.isUserInteractionEnabled = false
        addSubview(contentBorderView)

        // Rotation stem
        rotationStemView.backgroundColor = UIColor.systemBlue
        rotationStemView.isUserInteractionEnabled = false
        addSubview(rotationStemView)

        // Rotation handle
        addSubview(rotationHandle)

        // Corner handles
        addSubview(topLeftHandle)
        addSubview(topRightHandle)
        addSubview(bottomLeftHandle)
        addSubview(bottomRightHandle)

        // Badge View (Degree & Scale readout)
        badgeView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        badgeView.layer.cornerRadius = 10
        badgeView.clipsToBounds = true
        badgeView.alpha = 0
        badgeView.isUserInteractionEnabled = false

        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.frame = CGRect(x: 6, y: 2, width: 50, height: 16)
        badgeView.addSubview(badgeLabel)
        badgeView.frame = CGRect(x: 0, y: 0, width: 62, height: 20)
        addSubview(badgeView)

        // Action Toolbar
        actionToolbar.layer.cornerRadius = 18
        actionToolbar.clipsToBounds = true
        actionToolbar.layer.shadowColor = UIColor.black.cgColor
        actionToolbar.layer.shadowOpacity = 0.25
        actionToolbar.layer.shadowRadius = 8
        actionToolbar.layer.shadowOffset = CGSize(width: 0, height: 3)
        buildActionToolbar()
        addSubview(actionToolbar)

        // Color Palette Bar
        colorPaletteBar.layer.cornerRadius = 16
        colorPaletteBar.clipsToBounds = true
        colorPaletteBar.isHidden = true
        buildColorPalette()
        addSubview(colorPaletteBar)
    }

    // MARK: - Action Toolbar

    private func buildActionToolbar() {
        actionToolbar.contentView.subviews.forEach { $0.removeFromSuperview() }
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.distribution = .fillProportionally
        stack.translatesAutoresizingMaskIntoConstraints = false
        actionToolbar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: actionToolbar.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: actionToolbar.contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: actionToolbar.contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: actionToolbar.contentView.bottomAnchor, constant: -4),
        ])

        // 1. 90° Rotate button
        let rotBtn = makeToolbarButton(title: "90°", icon: "rotate.right") { [weak self] in
            self?.rotateBy90Degrees()
        }
        stack.addArrangedSubview(rotBtn)

        // 2. Duplicate button
        let dupBtn = makeToolbarButton(title: "Kopieren", icon: "doc.on.doc") { [weak self] in
            self?.onDuplicate?()
        }
        stack.addArrangedSubview(dupBtn)

        // 3. Color button (if handwriting strokes selected)
        if isHandwriting || !baseStrokes.isEmpty {
            let colBtn = makeToolbarButton(title: "Farbe", icon: "paintpalette.fill") { [weak self] in
                guard let self = self else { return }
                UIView.animate(withDuration: 0.2) {
                    self.colorPaletteBar.isHidden.toggle()
                }
            }
            stack.addArrangedSubview(colBtn)
        }

        // 4. Delete button
        let delBtn = makeToolbarButton(title: "Löschen", icon: "trash", tint: .systemRed) { [weak self] in
            self?.onDelete?()
        }
        stack.addArrangedSubview(delBtn)

        // 5. Done button
        let doneBtn = makeToolbarButton(title: "Fertig", icon: "checkmark", tint: .systemGreen) { [weak self] in
            self?.dismiss()
        }
        stack.addArrangedSubview(doneBtn)

        let totalWidth: CGFloat = (isHandwriting || !baseStrokes.isEmpty) ? 360 : 290
        actionToolbar.bounds = CGRect(x: 0, y: 0, width: totalWidth, height: 36)
    }

    private func buildColorPalette() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        colorPaletteBar.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: colorPaletteBar.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: colorPaletteBar.contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: colorPaletteBar.contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: colorPaletteBar.contentView.bottomAnchor, constant: -4),
        ])

        let colors: [UIColor] = [.black, .systemBlue, .systemRed, .systemGreen, .systemOrange, .systemPurple, .white]
        for c in colors {
            let dot = UIButton(type: .custom)
            dot.backgroundColor = c
            dot.layer.cornerRadius = 11
            dot.layer.borderWidth = (c == .white || c == .black) ? 1.0 : 0
            dot.layer.borderColor = UIColor.systemGray3.cgColor
            dot.widthAnchor.constraint(equalToConstant: 22).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 22).isActive = true
            dot.addAction(UIAction { [weak self] _ in
                self?.onChangeColor?(c)
                UIView.animate(withDuration: 0.2) { self?.colorPaletteBar.isHidden = true }
            }, for: .touchUpInside)
            stack.addArrangedSubview(dot)
        }

        colorPaletteBar.frame = CGRect(x: 0, y: 0, width: 230, height: 32)
    }

    private func makeToolbarButton(title: String, icon: String, tint: UIColor = .white, action: @escaping () -> Void) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 4
        cfg.baseForegroundColor = tint
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)

        var titleAttr = AttributedString(title)
        titleAttr.font = .systemFont(ofSize: 12, weight: .semibold)
        cfg.attributedTitle = titleAttr

        let btn = UIButton(configuration: cfg)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    // MARK: - Gestures

    private func setupGestures() {
        let touchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]

        // 1. Move Pan (center) - single touch only so 2 fingers pinch & rotate
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        movePan.maximumNumberOfTouches = 1
        movePan.allowedTouchTypes = touchTypes
        movePan.delegate = self
        addGestureRecognizer(movePan)
        self.movePan = movePan

        // 2. Rotation Pan
        let rotPan = UIPanGestureRecognizer(target: self, action: #selector(handleRotationPan(_:)))
        rotPan.allowedTouchTypes = touchTypes
        rotPan.delegate = self
        rotationHandle.addGestureRecognizer(rotPan)

        // 3. Corner Scale Pans
        for h in [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle] {
            let cornerPan = UIPanGestureRecognizer(target: self, action: #selector(handleCornerScalePan(_:)))
            cornerPan.allowedTouchTypes = touchTypes
            cornerPan.delegate = self
            h.addGestureRecognizer(cornerPan)
        }

        // 4. Two-finger Pinch & Rotate
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        self.pinch = pinch

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        rotate.delegate = self
        addGestureRecognizer(rotate)
        self.rotate = rotate
    }

    /// Explicitly tells the PKCanvasView's scroll and pinch recognizers to yield to our transform box
    func attachCanvasGestureRequirements(_ canvasView: PKCanvasView, additionalPanGesture: UIPanGestureRecognizer? = nil) {
        if let movePan {
            canvasView.panGestureRecognizer.require(toFail: movePan)
            additionalPanGesture?.require(toFail: movePan)
        }
        if let pinch {
            canvasView.pinchGestureRecognizer?.require(toFail: pinch)
            canvasView.panGestureRecognizer.require(toFail: pinch)
            additionalPanGesture?.require(toFail: pinch)
        }
        if let rotate {
            canvasView.pinchGestureRecognizer?.require(toFail: rotate)
            canvasView.panGestureRecognizer.require(toFail: rotate)
            additionalPanGesture?.require(toFail: rotate)
        }
        for h in [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle] {
            for gr in h.gestureRecognizers ?? [] {
                canvasView.panGestureRecognizer.require(toFail: gr)
                canvasView.pinchGestureRecognizer?.require(toFail: gr)
                additionalPanGesture?.require(toFail: gr)
            }
        }
        for gr in rotationHandle.gestureRecognizers ?? [] {
            canvasView.panGestureRecognizer.require(toFail: gr)
            canvasView.pinchGestureRecognizer?.require(toFail: gr)
            additionalPanGesture?.require(toFail: gr)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === movePan {
            // Never allow movePan to start if the user touched a corner handle, rotation handle, or toolbar
            if touch.view is CornerHandleView || touch.view is RotationHandleView {
                return false
            }
            if let v = touch.view {
                if v.isDescendant(of: rotationHandle) || v.isDescendant(of: actionToolbar) || v.isDescendant(of: colorPaletteBar) {
                    return false
                }
                for h in [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle] {
                    if v === h || v.isDescendant(of: h) {
                        return false
                    }
                }
            }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow simultaneous recognition between pinch and rotate on this transform box
        let isOurPinch = gestureRecognizer is UIPinchGestureRecognizer && gestureRecognizer.view === self
        let isOurRotate = gestureRecognizer is UIRotationGestureRecognizer && gestureRecognizer.view === self
        let otherIsOurPinch = otherGestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer.view === self
        let otherIsOurRotate = otherGestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer.view === self

        return (isOurPinch && otherIsOurRotate) || (isOurRotate && otherIsOurPinch)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Prevent scroll/pan/pinch gestures on parent views (like canvasView) from stealing touches while interacting with the transform box
        let isParentGesture = otherGestureRecognizer.view !== self && otherGestureRecognizer.view !== rotationHandle && !isCornerHandle(otherGestureRecognizer.view)
        if isParentGesture {
            if otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer {
                return true
            }
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    private func isCornerHandle(_ view: UIView?) -> Bool {
        return view === topLeftHandle || view === topRightHandle || view === bottomLeftHandle || view === bottomRightHandle
    }

    // MARK: - Move Handling (Verschieben)

    @objc private func handleMovePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let translation = gr.translation(in: sv)
        gr.setTranslation(.zero, in: sv)

        currentCenter.x += translation.x
        currentCenter.y += translation.y
        center = currentCenter

        triggerLiveUpdate()

        if gr.state == .ended || gr.state == .cancelled {
            triggerCommit()
        }
    }

    // MARK: - Corner Scaling Handling (Vergrößern / Verkleinern)

    @objc private func handleCornerScalePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        switch gr.state {
        case .began:
            let touchInParent = gr.location(in: sv)
            initialCornerDistance = max(hypot(touchInParent.x - currentCenter.x, touchInParent.y - currentCenter.y), 15)
            initialScaleOnCornerPan = currentScale
            showBadge(text: "\(Int(round(currentScale * 100)))%")
        case .changed:
            let touchInParent = gr.location(in: sv)
            let currentDist = hypot(touchInParent.x - currentCenter.x, touchInParent.y - currentCenter.y)
            let ratio = currentDist / initialCornerDistance
            currentScale = max(0.15, min(6.0, initialScaleOnCornerPan * ratio))

            updateLayout()
            showBadge(text: "\(Int(round(currentScale * 100)))%")
            triggerLiveUpdate()
        case .ended, .cancelled:
            hideBadge()
            triggerCommit()
        default:
            hideBadge()
        }
    }

    // MARK: - Rotation Handling (Drehen)

    @objc private func handleRotationPan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        switch gr.state {
        case .began:
            showBadge(text: "\(Int(round(currentRotation * 180 / .pi)) % 360)°")
        case .changed:
            let touchInParent = gr.location(in: sv)
            let vector = CGPoint(x: touchInParent.x - currentCenter.x, y: touchInParent.y - currentCenter.y)
            var angle = atan2(vector.y, vector.x) + .pi / 2
            angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
            if angle < 0 { angle += 2 * .pi }

            // Haptic angle snapping at 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
            let snapAngles: [CGFloat] = [0, .pi / 4, .pi / 2, 3 * .pi / 4, .pi, 5 * .pi / 4, 3 * .pi / 2, 7 * .pi / 4, 2 * .pi]
            for snap in snapAngles {
                if abs(angle - snap) < 0.08 || abs(angle - (snap - 2 * .pi)) < 0.08 {
                    if angle != snap {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    angle = (snap == 2 * .pi) ? 0 : snap
                    break
                }
            }

            currentRotation = angle
            transform = CGAffineTransform(rotationAngle: currentRotation)
            counterRotateToolbars()

            let deg = Int(round(angle * 180 / .pi)) % 360
            showBadge(text: "\(deg)°")
            triggerLiveUpdate()
        case .ended, .cancelled:
            hideBadge()
            triggerCommit()
        default:
            hideBadge()
        }
    }

    // MARK: - Two-finger Gestures

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        guard let sv = superview else { return }
        switch gr.state {
        case .began:
            initialPinchCenter = gr.location(in: sv)
            initialBoxCenterOnPinch = currentCenter
            showBadge(text: "\(Int(round(currentScale * 100)))%")
        case .changed:
            let touchLoc = gr.location(in: sv)
            let dx = touchLoc.x - initialPinchCenter.x
            let dy = touchLoc.y - initialPinchCenter.y
            currentCenter = CGPoint(x: initialBoxCenterOnPinch.x + dx, y: initialBoxCenterOnPinch.y + dy)
            currentScale = max(0.15, min(6.0, currentScale * gr.scale))
            gr.scale = 1.0
            updateLayout()
            showBadge(text: "\(Int(round(currentScale * 100)))%")
            triggerLiveUpdate()
        case .ended, .cancelled:
            hideBadge()
            triggerCommit()
        default:
            hideBadge()
        }
    }

    @objc private func handleRotate(_ gr: UIRotationGestureRecognizer) {
        if gr.state == .changed {
            currentRotation += gr.rotation
            gr.rotation = 0.0
            transform = CGAffineTransform(rotationAngle: currentRotation)
            counterRotateToolbars()

            let deg = Int(round(currentRotation * 180 / .pi)) % 360
            showBadge(text: "\(deg)°")
            triggerLiveUpdate()
        } else if gr.state == .ended || gr.state == .cancelled {
            hideBadge()
            triggerCommit()
        }
    }

    // MARK: - Quick 90° Rotate

    func rotateBy90Degrees() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        currentRotation = (currentRotation + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.transform = CGAffineTransform(rotationAngle: self.currentRotation)
            self.counterRotateToolbars()
        }
        let deg = Int(round(currentRotation * 180 / .pi)) % 360
        showBadge(text: "\(deg)°")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.hideBadge() }
        triggerLiveUpdate()
        triggerCommit()
    }

    // MARK: - Layout Updates

    func updateLayout() {
        let w = max(32, baseSize.width * currentScale)
        let h = max(32, baseSize.height * currentScale)
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        center = currentCenter

        contentBorderView.frame = bounds

        topLeftHandle.center     = CGPoint(x: 0, y: 0)
        topRightHandle.center    = CGPoint(x: w, y: 0)
        bottomLeftHandle.center  = CGPoint(x: 0, y: h)
        bottomRightHandle.center = CGPoint(x: w, y: h)

        let midX = w / 2
        rotationStemView.frame = CGRect(x: midX - 0.75, y: -30, width: 1.5, height: 30)
        rotationHandle.center = CGPoint(x: midX, y: -30)

        badgeView.center = CGPoint(x: midX, y: -56)
        actionToolbar.center = CGPoint(x: midX, y: -72)
        colorPaletteBar.center = CGPoint(x: midX, y: -116)

        counterRotateToolbars()
    }

    private func counterRotateToolbars() {
        // Keep toolbars and badge horizontal and readable regardless of box rotation
        let counter = CGAffineTransform(rotationAngle: -currentRotation)
        actionToolbar.transform = counter
        colorPaletteBar.transform = counter
        badgeView.transform = counter
    }

    private func showBadge(text: String) {
        badgeLabel.text = text
        UIView.animate(withDuration: 0.15) { self.badgeView.alpha = 1 }
    }

    private func hideBadge() {
        UIView.animate(withDuration: 0.25) { self.badgeView.alpha = 0 }
    }

    // MARK: - Trigger Callbacks

    func triggerLiveUpdate() {
        if !baseStrokes.isEmpty {
            onLiveUpdateStrokes?(currentCenter, currentScale, currentRotation)
        } else if targetElementView != nil {
            onLiveUpdateElement?(currentCenter, currentScale, currentRotation)
        }
    }

    func triggerCommit() {
        if !baseStrokes.isEmpty {
            onCommitStrokes?(currentCenter, currentScale, currentRotation)
        } else if targetElementView != nil {
            onCommitElement?(currentCenter, currentScale, currentRotation)
        }
    }

    func dismiss() {
        onDismiss?()
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }

    // Expand touch hit testing to include floating handles and toolbars
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 1. Toolbars
        if !actionToolbar.isHidden {
            let pt = convert(point, to: actionToolbar)
            if actionToolbar.bounds.insetBy(dx: -12, dy: -12).contains(pt) {
                return true
            }
        }
        if !colorPaletteBar.isHidden {
            let pt = convert(point, to: colorPaletteBar)
            if colorPaletteBar.bounds.insetBy(dx: -12, dy: -12).contains(pt) {
                return true
            }
        }

        // 2. Rotation handle
        let ptRot = convert(point, to: rotationHandle)
        if rotationHandle.bounds.insetBy(dx: -16, dy: -16).contains(ptRot) {
            return true
        }

        // 3. Corner handles
        for h in [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle] {
            let ptH = convert(point, to: h)
            if h.bounds.insetBy(dx: -16, dy: -16).contains(ptH) {
                return true
            }
        }

        // 4. Box body with generous hit target
        return bounds.insetBy(dx: -20, dy: -20).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard self.point(inside: point, with: event) else { return nil }

        // 1. Toolbars (highest priority)
        if !actionToolbar.isHidden {
            let ptInToolbar = convert(point, to: actionToolbar)
            if actionToolbar.bounds.insetBy(dx: -8, dy: -8).contains(ptInToolbar) {
                let ptInContent = convert(point, to: actionToolbar.contentView)
                if let hit = actionToolbar.contentView.hitTest(ptInContent, with: event) {
                    return hit
                }
                return actionToolbar
            }
        }
        if !colorPaletteBar.isHidden {
            let ptInPalette = convert(point, to: colorPaletteBar)
            if colorPaletteBar.bounds.insetBy(dx: -8, dy: -8).contains(ptInPalette) {
                let ptInContent = convert(point, to: colorPaletteBar.contentView)
                if let hit = colorPaletteBar.contentView.hitTest(ptInContent, with: event) {
                    return hit
                }
                return colorPaletteBar
            }
        }

        // 2. Rotation handle
        let ptInRot = convert(point, to: rotationHandle)
        if rotationHandle.bounds.insetBy(dx: -16, dy: -16).contains(ptInRot) {
            return rotationHandle
        }

        // 3. Corner handles
        for h in [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle] {
            let ptInH = convert(point, to: h)
            if h.bounds.insetBy(dx: -16, dy: -16).contains(ptInH) {
                return h
            }
        }

        // 4. Box body for moving
        return self
    }
}
