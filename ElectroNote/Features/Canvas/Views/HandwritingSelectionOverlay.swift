import UIKit

/// Fullscreen overlay for selecting a region of handwriting to recognise.
/// The user drags (finger or Pencil) to draw a rubber-band rectangle.
final class HandwritingSelectionOverlay: UIView {

    var onRegionSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint = .zero
    private(set) var selectionRect: CGRect = .null

    // MARK: - Subviews

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "Bereich auswählen und loslassen"
        l.textAlignment  = .center
        l.textColor      = .white
        l.font           = .systemFont(ofSize: 15, weight: .semibold)
        l.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        l.layer.cornerRadius = 12
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

    init() {
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear

        addSubview(hintLabel)
        addSubview(cancelButton)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.heightAnchor.constraint(equalToConstant: 40),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            cancelButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.allowedTouchTypes = [UITouch.TouchType.direct.rawValue  as NSNumber,
                                 UITouch.TouchType.pencil.rawValue  as NSNumber]
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Gesture

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let loc = gr.location(in: self)
        switch gr.state {
        case .began:
            startPoint    = loc
            selectionRect = .null
            setNeedsDisplay()
        case .changed:
            selectionRect = CGRect(
                x: min(startPoint.x, loc.x), y: min(startPoint.y, loc.y),
                width:  abs(loc.x - startPoint.x), height: abs(loc.y - startPoint.y)
            )
            setNeedsDisplay()
        case .ended:
            if selectionRect.width > 30 && selectionRect.height > 20 {
                onRegionSelected?(selectionRect)
            } else {
                selectionRect = .null
                setNeedsDisplay()
            }
        default:
            selectionRect = .null
            setNeedsDisplay()
        }
    }

    @objc private func cancelTapped() { onCancel?() }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard !selectionRect.isNull, selectionRect.width > 0 else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Dim area outside selection
        let outer = UIBezierPath(rect: bounds)
        outer.append(UIBezierPath(rect: selectionRect).reversing())
        UIColor.black.withAlphaComponent(0.3).setFill()
        outer.fill()

        // Dashed blue border
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [10, 5])
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(2.5)
        ctx.stroke(selectionRect.insetBy(dx: 1.25, dy: 1.25))
        ctx.restoreGState()

        // Corner handles
        UIColor.systemBlue.setFill()
        for corner in selectionRect.cornerPoints {
            UIBezierPath(ovalIn: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10)).fill()
        }
    }
}

private extension CGRect {
    var cornerPoints: [CGPoint] {
        [origin,
         CGPoint(x: maxX, y: minY),
         CGPoint(x: minX, y: maxY),
         CGPoint(x: maxX, y: maxY)]
    }
}
