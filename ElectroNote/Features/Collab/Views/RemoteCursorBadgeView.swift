import UIKit

final class RemoteCursorBadgeView: UIView {
    private let dotView = UIView()
    private let label = UILabel()
    private var fadeTimer: Timer?

    init(name: String, colorHex: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 26))
        isUserInteractionEnabled = false

        let peerColor = UIColor(hex: colorHex) ?? .systemBlue

        dotView.frame = CGRect(x: 0, y: 7, width: 12, height: 12)
        dotView.backgroundColor = peerColor
        dotView.layer.cornerRadius = 6
        dotView.layer.borderColor = UIColor.white.cgColor
        dotView.layer.borderWidth = 1.5
        addSubview(dotView)

        label.frame = CGRect(x: 16, y: 2, width: 100, height: 22)
        label.text = name
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.backgroundColor = peerColor.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.sizeToFit()
        label.frame.size.width += 12
        label.frame.size.height = 20
        label.frame.origin.x = 16
        label.frame.origin.y = 3
        addSubview(label)

        self.frame.size.width = label.frame.maxX + 4
        self.frame.size.height = 26
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePosition(_ point: CGPoint) {
        self.center = CGPoint(x: point.x + frame.width / 2, y: point.y + frame.height / 2)
        self.alpha = 1.0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.5) {
                self?.alpha = 0.0
            }
        }
    }
}


