import UIKit
import PencilKit

final class StickyNoteView: UIView, UITextViewDelegate, PKCanvasViewDelegate {

    let noteId: UUID

    var onMoved: ((CGPoint) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var onDrawingChanged: ((Data) -> Void)?
    var onDelete: (() -> Void)?

    static let stickyColors: [UIColor] = [
        UIColor(red: 1.00, green: 0.94, blue: 0.50, alpha: 1),  // yellow
        UIColor(red: 1.00, green: 0.80, blue: 0.86, alpha: 1),  // pink
        UIColor(red: 0.67, green: 0.84, blue: 1.00, alpha: 1),  // blue
        UIColor(red: 0.76, green: 0.98, blue: 0.76, alpha: 1),  // green
    ]

    static let noteSize = CGSize(width: 240, height: 180)

    private let headerView = UIView()
    private let dragHandle = UIImageView()
    private let modeBtn    = UIButton(type: .custom)
    private let deleteBtn  = UIButton(type: .custom)

    private let textView   = UITextView()
    private let canvasView = PKCanvasView()

    private var isPenMode = true

    init(note: StickyNote) {
        self.noteId = note.id
        super.init(frame: CGRect(origin: CGPoint(x: note.x, y: note.y), size: Self.noteSize))

        let color = Self.stickyColors[note.colorIndex % Self.stickyColors.count]
        let darker = color.withAlphaComponent(0.65)

        backgroundColor = color
        layer.cornerRadius  = 10
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowOffset  = CGSize(width: 0, height: 3)
        layer.shadowRadius  = 6

        // Header drag strip
        headerView.frame = CGRect(x: 0, y: 0, width: Self.noteSize.width, height: 34)
        headerView.backgroundColor = darker
        headerView.layer.cornerRadius = 10
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        headerView.isUserInteractionEnabled = true
        addSubview(headerView)

        // Drag handle indicator in header
        dragHandle.image = UIImage(systemName: "line.3.horizontal")
        dragHandle.tintColor = UIColor.black.withAlphaComponent(0.4)
        dragHandle.contentMode = .scaleAspectFit
        dragHandle.frame = CGRect(x: 10, y: 7, width: 22, height: 20)
        headerView.addSubview(dragHandle)

        // Mode switch button (Pen vs Keyboard)
        let modeCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        modeBtn.setImage(UIImage(systemName: "pencil.and.scribble", withConfiguration: modeCfg), for: .normal)
        modeBtn.tintColor = UIColor.black.withAlphaComponent(0.6)
        modeBtn.frame = CGRect(x: 40, y: 2, width: 30, height: 30)
        modeBtn.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        headerView.addSubview(modeBtn)

        // Delete button
        let delCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        deleteBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: delCfg), for: .normal)
        deleteBtn.tintColor = UIColor.black.withAlphaComponent(0.45)
        deleteBtn.frame = CGRect(x: Self.noteSize.width - 34, y: 2, width: 30, height: 30)
        deleteBtn.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
        headerView.addSubview(deleteBtn)

        let contentRect = CGRect(x: 8, y: 38, width: Self.noteSize.width - 16, height: Self.noteSize.height - 46)

        // Text view (underneath canvas or active in keyboard mode)
        textView.frame = contentRect
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .black
        textView.text = note.text
        textView.delegate = self
        textView.isScrollEnabled = false
        addSubview(textView)

        // Transparent PKCanvasView for handwriting inside the sticky note
        canvasView.frame = contentRect
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput  // Apple Pencil & finger handwriting
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2.2)
        canvasView.delegate = self
        if let data = note.drawingData, let d = try? PKDrawing(data: data) {
            canvasView.drawing = d
        }
        addSubview(canvasView)

        // Pan gesture on header for moving the note
        let panHeader = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panHeader.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        headerView.addGestureRecognizer(panHeader)

        updateModeUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleMode() {
        isPenMode.toggle()
        updateModeUI()
    }

    private func updateModeUI() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        if isPenMode {
            modeBtn.setImage(UIImage(systemName: "pencil.and.scribble", withConfiguration: cfg), for: .normal)
            modeBtn.tintColor = UIColor.systemBlue
            canvasView.isUserInteractionEnabled = true
            bringSubviewToFront(canvasView)
            textView.resignFirstResponder()
        } else {
            modeBtn.setImage(UIImage(systemName: "keyboard", withConfiguration: cfg), for: .normal)
            modeBtn.tintColor = UIColor.black.withAlphaComponent(0.6)
            canvasView.isUserInteractionEnabled = false
            bringSubviewToFront(textView)
            textView.becomeFirstResponder()
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let delta = gr.translation(in: sv)
        gr.setTranslation(.zero, in: sv)

        frame.origin.x += delta.x
        frame.origin.y += delta.y

        onMoved?(frame.origin)
    }

    @objc private func didTapDelete() {
        onDelete?()
    }

    // MARK: - PKCanvasViewDelegate
    func canvasViewDrawingDidChange(_ cv: PKCanvasView) {
        let data = cv.drawing.dataRepresentation()
        onDrawingChanged?(data)
    }

    // MARK: - UITextViewDelegate
    func textViewDidChange(_ tv: UITextView) {
        onTextChanged?(tv.text)
    }
}
