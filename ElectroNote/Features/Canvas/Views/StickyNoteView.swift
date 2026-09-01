import UIKit

final class StickyNoteView: UIView, UITextViewDelegate {

    let noteId: UUID

    var onMoved: ((CGPoint) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var onDelete: (() -> Void)?

    static let stickyColors: [UIColor] = [
        UIColor(red: 1.00, green: 0.94, blue: 0.50, alpha: 1),  // yellow
        UIColor(red: 1.00, green: 0.80, blue: 0.86, alpha: 1),  // pink
        UIColor(red: 0.67, green: 0.84, blue: 1.00, alpha: 1),  // blue
        UIColor(red: 0.76, green: 0.98, blue: 0.76, alpha: 1),  // green
    ]

    static let noteSize = CGSize(width: 200, height: 160)

    private let textView   = UITextView()
    private let headerView = UIView()
    private let deleteBtn  = UIButton(type: .custom)

    init(note: StickyNote) {
        self.noteId = note.id
        super.init(frame: CGRect(origin: .zero, size: Self.noteSize))

        let color = Self.stickyColors[note.colorIndex % Self.stickyColors.count]
        let darker = color.withAlphaComponent(0.7)

        layer.cornerRadius  = 4
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset  = CGSize(width: 0, height: 2)
        layer.shadowRadius  = 5

        // Header strip (drag area)
        headerView.frame = CGRect(x: 0, y: 0, width: Self.noteSize.width, height: 28)
        headerView.backgroundColor = darker
        headerView.layer.cornerRadius = 4
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        // Body
        backgroundColor = color

        // Delete button
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        deleteBtn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        deleteBtn.tintColor = UIColor.black.withAlphaComponent(0.5)
        deleteBtn.frame = CGRect(x: Self.noteSize.width - 28, y: 0, width: 28, height: 28)
        deleteBtn.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
        addSubview(deleteBtn)

        // Text view
        textView.frame = CGRect(x: 8, y: 32, width: Self.noteSize.width - 16, height: Self.noteSize.height - 40)
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .black
        textView.text = note.text
        textView.delegate = self
        textView.isScrollEnabled = false
        addSubview(textView)

        // Pan gesture on header (drag to move)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        headerView.addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let t = gr.translation(in: sv)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        gr.setTranslation(.zero, in: sv)
        if gr.state == .ended || gr.state == .cancelled {
            onMoved?(frame.origin)
        }
    }

    @objc private func didTapDelete() { onDelete?() }

    func textViewDidChange(_ tv: UITextView) { onTextChanged?(tv.text) }
}
