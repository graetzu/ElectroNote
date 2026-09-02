import UIKit

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

/// Fullscreen lasso selection overlay for selecting handwriting or math equations.
/// The user draws a freehand lasso around the handwriting using finger or Apple Pencil.
final class HandwritingSelectionOverlay: UIView {

    var onLassoSelected: (([CGPoint], CGRect) -> Void)?
    var onCancel: (() -> Void)?

    let mode: SelectionMode
    private var lassoPoints: [CGPoint] = []

    // MARK: - Subviews

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

    // MARK: - Init

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

    // MARK: - Gesture

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

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard lassoPoints.count > 1 else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let path = UIBezierPath()
        path.move(to: lassoPoints[0])
        for p in lassoPoints.dropFirst() {
            path.addLine(to: p)
        }
        path.close()

        // Dim area outside selection
        let outer = UIBezierPath(rect: bounds)
        outer.append(path.reversing())
        UIColor.black.withAlphaComponent(0.25).setFill()
        outer.fill()

        // Subtle fill inside lasso
        mode.tintColor.withAlphaComponent(0.12).setFill()
        path.fill()

        // Dashed glowing lasso stroke
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setStrokeColor(mode.tintColor.cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Start point indicator
        if let first = lassoPoints.first {
            mode.tintColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)).fill()
        }
    }
}
