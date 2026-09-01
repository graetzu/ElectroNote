import UIKit

/// Overlay that lets the user tap or drag to pick a position for text insertion.
/// A crosshair follows the finger while dragging; releasing places the text.
final class TextPositionOverlay: UIView {

    var onPositionSelected: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var trackingPoint: CGPoint?

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text            = "Antippen wo der Text erscheinen soll"
        l.textAlignment   = .center
        l.textColor       = .white
        l.font            = .systemFont(ofSize: 15, weight: .semibold)
        l.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.85)
        l.layer.cornerRadius = 12
        l.clipsToBounds   = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title               = "Abbrechen"
        cfg.baseBackgroundColor = UIColor.secondarySystemFill
        cfg.baseForegroundColor = .label
        cfg.cornerStyle         = .medium
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    init() {
        super.init(frame: .zero)
        isOpaque        = false
        backgroundColor = UIColor.black.withAlphaComponent(0.08)

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

        // Tap for quick placement
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        // Pan for crosshair preview + placement on release
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.allowedTouchTypes = [UITouch.TouchType.direct.rawValue  as NSNumber,
                                 UITouch.TouchType.pencil.rawValue  as NSNumber]
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Gestures

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let pt = gr.location(in: self)
        flashCrosshair(at: pt) { [weak self] in self?.onPositionSelected?(pt) }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let loc = gr.location(in: self)
        switch gr.state {
        case .began, .changed:
            trackingPoint = loc
            setNeedsDisplay()
        case .ended:
            trackingPoint = nil
            setNeedsDisplay()
            flashCrosshair(at: loc) { [weak self] in self?.onPositionSelected?(loc) }
        default:
            trackingPoint = nil
            setNeedsDisplay()
        }
    }

    @objc private func cancelTapped() { onCancel?() }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let p = trackingPoint, let ctx = UIGraphicsGetCurrentContext() else { return }
        drawCrosshair(at: p, in: ctx, alpha: 1)
    }

    private func drawCrosshair(at p: CGPoint, in ctx: CGContext, alpha: CGFloat) {
        let r: CGFloat = 22
        // Circle fill
        ctx.setFillColor(UIColor.systemIndigo.withAlphaComponent(0.15 * alpha).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))

        // Cross lines
        ctx.setStrokeColor(UIColor.systemIndigo.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: p.x - r, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + r, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: p.y - r)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + r))
        ctx.strokePath()

        // Center dot
        ctx.setFillColor(UIColor.systemIndigo.withAlphaComponent(alpha).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
    }

    private func flashCrosshair(at point: CGPoint, completion: @escaping () -> Void) {
        let overlay = UIView(frame: bounds)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        addSubview(overlay)

        UIView.animate(withDuration: 0.15, animations: {
            overlay.alpha = 0.6
        }) { _ in
            UIView.animate(withDuration: 0.15, animations: {
                overlay.alpha = 0
            }) { _ in
                overlay.removeFromSuperview()
                completion()
            }
        }
    }
}
