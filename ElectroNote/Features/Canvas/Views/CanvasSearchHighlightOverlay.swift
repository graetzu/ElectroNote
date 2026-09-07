import UIKit

final class CanvasSearchHighlightOverlay: UIView {
    private var highlightViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHighlights(matches: [SearchResultItem], activeIndex: Int) {
        // Remove old views
        highlightViews.forEach { $0.removeFromSuperview() }
        highlightViews.removeAll()

        guard !matches.isEmpty else { return }

        for (idx, match) in matches.enumerated() {
            let isActive = (idx == activeIndex)
            let box = UIView()
            box.frame = match.canvasRect.insetBy(dx: -4, dy: -2)
            box.layer.cornerRadius = 4
            box.clipsToBounds = true
            box.isUserInteractionEnabled = false

            if isActive {
                box.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.45)
                box.layer.borderColor = UIColor.systemOrange.cgColor
                box.layer.borderWidth = 2.0

                // Subtle pop animation for the active highlight
                box.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                    box.transform = .identity
                }
            } else {
                box.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.30)
                box.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.80).cgColor
                box.layer.borderWidth = 1.0
            }

            addSubview(box)
            highlightViews.append(box)
        }
    }

    func clear() {
        highlightViews.forEach { $0.removeFromSuperview() }
        highlightViews.removeAll()
    }
}
