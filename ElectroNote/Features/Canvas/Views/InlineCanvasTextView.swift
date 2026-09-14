import UIKit

protocol InlineCanvasTextViewDelegate: AnyObject {
    func inlineCanvasTextViewDidCommit(_ view: InlineCanvasTextView, text: String, origin: CGPoint, existingId: UUID?)
    func inlineCanvasTextViewDidCancel(_ view: InlineCanvasTextView, existingId: UUID?)
    func inlineCanvasTextViewDidChangeSize(_ view: InlineCanvasTextView)
    func inlineCanvasTextViewRequestDelete(_ view: InlineCanvasTextView, existingId: UUID)
}

final class InlineCanvasTextView: UIView, UITextViewDelegate {
    weak var delegate: InlineCanvasTextViewDelegate?

    let elementId: UUID?
    var contentOrigin: CGPoint
    var fontSize: CGFloat {
        didSet {
            updateFontAndLayout()
        }
    }
    var fontDesign: String? {
        didSet {
            updateFontAndLayout()
        }
    }
    var fontColorHex: String? {
        didSet {
            updateTextColor()
        }
    }
    let isDarkCanvas: Bool
    let canvasWidth: CGFloat

    let containerView = UIView()
    let headerView = UIView()
    let textView = UITextView()
    let placeholderLabel = UILabel()

    private let sizeLabel = UILabel()
    private let decreaseSizeButton = UIButton(type: .system)
    private let increaseSizeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    init(
        elementId: UUID?,
        contentOrigin: CGPoint,
        initialText: String,
        fontSize: CGFloat = 22,
        fontDesign: String? = nil,
        fontColorHex: String? = nil,
        isDarkCanvas: Bool,
        canvasWidth: CGFloat
    ) {
        self.elementId = elementId
        self.contentOrigin = contentOrigin
        self.fontSize = max(12, min(fontSize, 120))
        self.fontDesign = fontDesign
        self.fontColorHex = fontColorHex
        self.isDarkCanvas = isDarkCanvas
        self.canvasWidth = canvasWidth

        super.init(frame: .zero)
        setupViews(initialText: initialText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(initialText: String) {
        backgroundColor = .clear

        // Container styling
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 10
        containerView.layer.borderWidth = 1.5
        containerView.layer.borderColor = UIColor.systemBlue.cgColor

        if isDarkCanvas {
            containerView.backgroundColor = UIColor(white: 0.16, alpha: 0.96)
            containerView.layer.shadowColor = UIColor.black.cgColor
            containerView.layer.shadowOpacity = 0.5
        } else {
            containerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
            containerView.layer.shadowColor = UIColor.black.cgColor
            containerView.layer.shadowOpacity = 0.15
        }
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(containerView)

        // Header view (toolbar)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = isDarkCanvas ? UIColor(white: 0.22, alpha: 0.9) : UIColor.secondarySystemFill
        headerView.layer.cornerRadius = 8
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.addSubview(headerView)

        // Size controls: [A-] [22 pt] [A+]
        decreaseSizeButton.setTitle("A-", for: .normal)
        decreaseSizeButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        decreaseSizeButton.addTarget(self, action: #selector(decreaseFontSize), for: .touchUpInside)

        sizeLabel.text = "\(Int(fontSize)) pt"
        sizeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        sizeLabel.textColor = isDarkCanvas ? .white : .secondaryLabel
        sizeLabel.textAlignment = .center

        increaseSizeButton.setTitle("A+", for: .normal)
        increaseSizeButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        increaseSizeButton.addTarget(self, action: #selector(increaseFontSize), for: .touchUpInside)

        // Done button
        doneButton.setTitle("✓ Fertig", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        doneButton.tintColor = .systemBlue
        doneButton.addTarget(self, action: #selector(commitAndDismiss), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [decreaseSizeButton, sizeLabel, increaseSizeButton])
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerStack)

        if elementId != nil {
            deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
            deleteButton.tintColor = .systemRed
            deleteButton.addTarget(self, action: #selector(handleDelete), for: .touchUpInside)
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(deleteButton)
        }

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            headerStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            doneButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])

        if elementId != nil {
            NSLayoutConstraint.activate([
                deleteButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8),
                deleteButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
            ])
        }

        // Text view
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.text = initialText
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        updateFontAndLayout()
        updateTextColor()
        containerView.addSubview(textView)

        // Placeholder
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Text eingeben… (Esc oder ⌘↵ zum Beenden)"
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = isDarkCanvas ? UIColor(white: 0.55, alpha: 1.0) : UIColor.placeholderText
        placeholderLabel.isHidden = !initialText.isEmpty
        containerView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor)
        ])

        updateSize()
    }

    private func updateFontAndLayout() {
        let font = InfiniteNotebookViewController.fontFor(design: fontDesign, size: fontSize)
        textView.font = font
        placeholderLabel.font = font
        sizeLabel.text = "\(Int(fontSize)) pt"
        updateSize()
    }

    private func updateTextColor() {
        if let hex = fontColorHex, let c = UIColor(hex: hex) {
            textView.textColor = c
        } else {
            textView.textColor = isDarkCanvas ? .white : .black
        }
    }

    @objc private func decreaseFontSize() {
        fontSize = max(10, fontSize - 2)
    }

    @objc private func increaseFontSize() {
        fontSize = min(96, fontSize + 2)
    }

    @objc private func handleDelete() {
        guard let id = elementId else { return }
        delegate?.inlineCanvasTextViewRequestDelete(self, existingId: id)
    }

    @objc func commitAndDismiss() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        delegate?.inlineCanvasTextViewDidCommit(self, text: trimmed, origin: contentOrigin, existingId: elementId)
    }

    func focus() {
        textView.becomeFirstResponder()
        if !textView.text.isEmpty {
            let endPosition = textView.endOfDocument
            textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
        }
    }

    func updateSize() {
        let minW: CGFloat = 280
        let maxW: CGFloat = max(minW, canvasWidth - contentOrigin.x - 30)

        let availableTextW = maxW - 32
        let rawText = textView.text ?? ""
        let textToMeasure: String = rawText.isEmpty ? (placeholderLabel.text ?? "") : rawText
        let font = textView.font ?? UIFont.systemFont(ofSize: fontSize)
        let rect = (textToMeasure as NSString).boundingRect(
            with: CGSize(width: availableTextW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        let calculatedW = max(minW, min(rect.width + 48, maxW))
        let calculatedH = max(80, rect.height + 64)

        self.frame = CGRect(x: contentOrigin.x, y: contentOrigin.y, width: calculatedW, height: calculatedH)
        delegate?.inlineCanvasTextViewDidChangeSize(self)
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSize()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return true
    }

    // MARK: - Key Commands (Esc to finish, ⌘+Enter to finish)

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Fertig", action: #selector(commitAndDismiss), input: "\r", modifierFlags: .command),
            UIKeyCommand(title: "Fertig", action: #selector(commitAndDismiss), input: UIKeyCommand.inputEscape)
        ]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.key?.keyCode == .keyboardEscape {
                commitAndDismiss()
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}
