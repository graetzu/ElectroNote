import SwiftUI
import PencilKit

struct MathPanelView: View {
    @StateObject private var vm = MathViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modus", selection: $vm.mode) {
                    ForEach(MathViewModel.Mode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                Group {
                    switch vm.mode {
                    case .calculator:  calculatorTab
                    case .handwriting: handwritingTab
                    case .plotter:     plotterTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Mathe")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Rechner

    private var calculatorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Expression input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ausdruck").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("z. B.  2 + 2  oder  sin(π/2)", text: $vm.expression)
                            .font(.title3.monospaced())
                            .onChange(of: vm.expression) { vm.evaluateExpression() }
                            .submitLabel(.done)
                        if !vm.expression.isEmpty {
                            Button { vm.clear() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                }

                // Quick-insert symbols
                symbolBar

                // Result
                if !vm.result.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ergebnis").font(.caption).foregroundStyle(.secondary)
                        Text("= \(vm.result)")
                            .font(.largeTitle.bold().monospaced())
                            .foregroundStyle(vm.resultIsError ? .red : .blue)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemFill)))
                }
            }
            .padding()
        }
    }

    private var symbolBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schnelleingabe").font(.caption).foregroundStyle(.secondary)
            let symbols: [(String, String)] = [
                ("π", "π"), ("√", "sqrt("), ("^", "^"), ("²", "²"),
                ("sin", "sin("), ("cos", "cos("), ("tan", "tan("),
                ("log", "log("), ("ln", "ln("), ("(", "("), (")", ")"),
            ]
            FlowLayout(spacing: 8) {
                ForEach(symbols, id: \.0) { label, val in
                    Button { vm.append(val) } label: {
                        Text(label)
                            .font(.callout.monospaced())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(.secondarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Handschrift

    private var handwritingTab: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Canvas for handwriting
                ZStack(alignment: .topLeading) {
                    Color.white
                    if vm.drawing.strokes.isEmpty {
                        Text("Formel mit Apple Pencil schreiben…")
                            .foregroundStyle(.tertiary)
                            .padding(20)
                    }
                    MathCanvasRepresentable(drawing: $vm.drawing)
                }
                .frame(height: geo.size.height * 0.4)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                Divider()

                // Controls + result
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            vm.recogniseHandwriting(canvasSize: CGSize(
                                width: geo.size.width - 32,
                                height: geo.size.height * 0.4
                            ))
                        } label: {
                            Label("Erkennen", systemImage: "text.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.drawing.strokes.isEmpty || vm.recognitionState == .processing)

                        Button { vm.clearHandwriting() } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.drawing.strokes.isEmpty)
                    }

                    if vm.recognitionState == .processing {
                        ProgressView("Erkenne…")
                    }

                    if !vm.recognizedText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Erkannt", systemImage: "text.viewfinder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(vm.recognizedText)
                                .font(.title3.monospaced())

                            if !vm.result.isEmpty {
                                Text("= \(vm.result)")
                                    .font(.title.bold().monospaced())
                                    .foregroundStyle(vm.resultIsError ? .red : .blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemFill)))
                    }
                }
                .padding()

                Spacer()
            }
        }
    }

    // MARK: - Plotter

    private var plotterTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // f(x) input
                VStack(alignment: .leading, spacing: 6) {
                    Text("f(x) =").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("x^2 + 2*x - 1", text: $vm.functionExpression)
                            .font(.title3.monospaced())
                        Button {
                            vm.computePlot()
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                }

                // x range
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("x min").font(.caption).foregroundStyle(.secondary)
                        TextField("-10", value: $vm.xMin, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("x max").font(.caption).foregroundStyle(.secondary)
                        TextField("10", value: $vm.xMax, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Plot") { vm.computePlot() }
                        .buttonStyle(.bordered)
                }

                // Graph
                if !vm.plotPoints.isEmpty {
                    FunctionPlotView(
                        points:  vm.plotPoints,
                        xMin:    vm.xMin,
                        xMax:    vm.xMax,
                        yRange:  vm.plotYRange
                    )
                    .frame(height: 320)
                    .shadow(radius: 4)
                } else {
                    Button {
                        vm.computePlot()
                    } label: {
                        Label("Graphen zeichnen", systemImage: "waveform.path")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .onAppear { if vm.plotPoints.isEmpty { vm.computePlot() } }
    }
}

// MARK: - Minimal PencilKit wrapper for math input

private struct MathCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let c = PKCanvasView()
        c.drawing = drawing
        c.delegate = context.coordinator
        c.backgroundColor = .white
        c.overrideUserInterfaceStyle = .light
        c.drawingPolicy = .anyInput

        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: c)
        picker.addObserver(c)
        context.coordinator.picker = picker
        DispatchQueue.main.async { c.becomeFirstResponder() }
        return c
    }

    func updateUIView(_ c: PKCanvasView, context: Context) {
        if c.drawing != drawing { c.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: MathCanvasRepresentable
        var picker: PKToolPicker?
        init(_ p: MathCanvasRepresentable) { parent = p }
        func canvasViewDrawingDidChange(_ c: PKCanvasView) { parent.drawing = c.drawing }
    }
}

// MARK: - Simple flow layout for symbol bar

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX,
                                          y: bounds.minY + frame.minY),
                              proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxW = max(maxW, x)
        }

        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}

// MARK: - Scientific Calculator Persistence & State

public struct CalculationHistoryEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let expression: String
    public let result: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), expression: String, result: String) {
        self.id = id
        self.timestamp = timestamp
        self.expression = expression
        self.result = result
    }
}

@MainActor
public final class ScientificCalculatorStore: ObservableObject {
    public static let shared = ScientificCalculatorStore()

    @Published public var expression: String {
        didSet {
            UserDefaults.standard.set(expression, forKey: "scicalc_expression")
            evaluateLive()
        }
    }
    @Published public var result: String {
        didSet {
            UserDefaults.standard.set(result, forKey: "scicalc_result")
        }
    }
    @Published public var livePreviewResult: String = ""
    @Published public var resultIsError: Bool = false
    @Published public var isDegreeMode: Bool {
        didSet {
            UserDefaults.standard.set(isDegreeMode, forKey: "scicalc_isDegreeMode")
            evaluateLive()
        }
    }
    @Published public var lastAnswer: String {
        didSet {
            UserDefaults.standard.set(lastAnswer, forKey: "scicalc_lastAnswer")
        }
    }
    @Published public var cursorIndex: Int = 0
    @Published public var is2ndActive: Bool = false
    @Published public var showHistory: Bool = false
    @Published public var isMinimized: Bool = false
    @Published public var history: [CalculationHistoryEntry] = []
    @Published public var dragOffset: CGSize = .zero

    private let evaluator = MathEvaluator()

    public init() {
        let savedExpr = UserDefaults.standard.string(forKey: "scicalc_expression") ?? ""
        self.expression = savedExpr
        self.result = UserDefaults.standard.string(forKey: "scicalc_result") ?? ""
        self.isDegreeMode = UserDefaults.standard.object(forKey: "scicalc_isDegreeMode") as? Bool ?? true
        self.lastAnswer = UserDefaults.standard.string(forKey: "scicalc_lastAnswer") ?? ""
        self.cursorIndex = savedExpr.count
        loadHistory()
        evaluateLive()
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "scicalc_history"),
           let list = try? JSONDecoder().decode([CalculationHistoryEntry].self, from: data) {
            self.history = list
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "scicalc_history")
        }
    }

    // MARK: - Cursor-Aware Calculator Operations

    public func insertToken(_ token: String) {
        let validIdx = min(max(0, cursorIndex), expression.count)
        let idx = expression.index(expression.startIndex, offsetBy: validIdx)
        expression.insert(contentsOf: token, at: idx)
        cursorIndex = validIdx + token.count
    }

    public func insertFunction(_ fn: String) {
        insertToken(fn + "(")
    }

    public func append(_ symbol: String) {
        insertToken(symbol)
    }

    public func appendFunction(_ fn: String) {
        insertFunction(fn)
    }

    public func backspace() {
        let validIdx = min(max(0, cursorIndex), expression.count)
        guard validIdx > 0 && !expression.isEmpty else { return }

        let prefix = String(expression.prefix(validIdx))
        let suffix = String(expression.suffix(expression.count - validIdx))

        let multiTokens = [
            "arcsin(", "arccos(", "arctan(", "sqrt(", "cbrt(",
            "log10(", "log2(", "fact(", "sin(", "cos(", "tan(",
            "log(", "ln(", "exp(", "abs(", "Ans", "π", "²", "³",
            " + ", " − ", " × ", " ÷ ", " / ", " * "
        ]

        var newPrefix = prefix
        var matched = false
        for token in multiTokens {
            if newPrefix.hasSuffix(token) {
                newPrefix.removeLast(token.count)
                matched = true
                break
            }
        }
        if !matched {
            newPrefix.removeLast()
        }

        expression = newPrefix + suffix
        cursorIndex = newPrefix.count
    }

    public func moveCursorLeft() {
        cursorIndex = max(0, cursorIndex - 1)
    }

    public func moveCursorRight() {
        cursorIndex = min(expression.count, cursorIndex + 1)
    }

    public func moveCursorToStart() {
        cursorIndex = 0
    }

    public func moveCursorToEnd() {
        cursorIndex = expression.count
    }

    public func clear() {
        expression = ""
        result = ""
        livePreviewResult = ""
        resultIsError = false
        cursorIndex = 0
    }

    public func evaluateLive() {
        guard !expression.isEmpty else {
            livePreviewResult = ""
            return
        }
        switch evaluator.evaluate(expression, isDegreeMode: isDegreeMode) {
        case .success(let val):
            livePreviewResult = formatResult(val)
        case .failure:
            livePreviewResult = ""
        }
    }

    public func calculate() {
        guard !expression.isEmpty else { return }
        switch evaluator.evaluate(expression, isDegreeMode: isDegreeMode) {
        case .success(let val):
            let formatted = formatResult(val)
            result = formatted
            resultIsError = false
            lastAnswer = formatted

            let entry = CalculationHistoryEntry(expression: expression, result: formatted)
            if history.first?.expression != entry.expression || history.first?.result != entry.result {
                history.insert(entry, at: 0)
                if history.count > 40 { history.removeLast() }
                saveHistory()
            }
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)

        case .failure(let err):
            result = err.localizedDescription ?? "Fehler"
            resultIsError = true
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
        }
    }

    public func toggleDegreeMode() {
        isDegreeMode.toggle()
        if !expression.isEmpty {
            evaluateLive()
            if !result.isEmpty && !resultIsError {
                calculate()
            }
        }
    }

    public func toggle2nd() {
        is2ndActive.toggle()
    }

    public func insertAns() {
        guard !lastAnswer.isEmpty else { return }
        insertToken(lastAnswer)
    }

    public func toggleSign() {
        guard !expression.isEmpty else {
            insertToken("-")
            return
        }
        if expression.hasPrefix("-(") && expression.hasSuffix(")") {
            expression.removeFirst(2)
            expression.removeLast()
            cursorIndex = max(0, min(expression.count, cursorIndex - 2))
        } else {
            expression = "-(" + expression + ")"
            cursorIndex = min(expression.count, cursorIndex + 2)
        }
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    public func restoreHistoryEntry(_ entry: CalculationHistoryEntry) {
        expression = entry.expression
        result = entry.result
        resultIsError = false
        cursorIndex = expression.count
        showHistory = false
    }

    private func formatResult(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return "Unendlich" }
        if value == value.rounded() && abs(value) < 1e12 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%g", value)
    }
}

// MARK: - Calculator Expression Text View (Full Editing & Cursor Support)

public struct CalculatorExpressionTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorIndex: Int
    var isKeyboardActive: Bool
    var onCommit: (() -> Void)? = nil

    public init(
        text: Binding<String>,
        cursorIndex: Binding<Int>,
        isKeyboardActive: Bool,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self._cursorIndex = cursorIndex
        self.isKeyboardActive = isKeyboardActive
        self.onCommit = onCommit
    }

    public func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        tv.textColor = UIColor.label
        tv.backgroundColor = UIColor.clear
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = true
        tv.textContainer.lineBreakMode = .byCharWrapping
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.keyboardType = .numbersAndPunctuation
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.tintColor = UIColor.systemTeal
        tv.returnKeyType = .done
        return tv
    }

    public func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }

        let currentLoc = tv.selectedRange.location
        let validCursor = min(max(0, cursorIndex), text.count)
        if currentLoc != validCursor && tv.selectedRange.length == 0 {
            tv.selectedRange = NSRange(location: validCursor, length: 0)
            tv.scrollRangeToVisible(NSRange(location: validCursor, length: 0))
        }

        if isKeyboardActive {
            if !tv.isFirstResponder {
                tv.becomeFirstResponder()
            }
        } else {
            if tv.isFirstResponder {
                tv.resignFirstResponder()
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: CalculatorExpressionTextView

        init(_ parent: CalculatorExpressionTextView) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.cursorIndex = textView.selectedRange.location
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            parent.cursorIndex = textView.selectedRange.location
        }

        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onCommit?()
                return false
            }
            return true
        }
    }
}

// MARK: - Scientific Calculator Floating View

public struct ScientificCalculatorFloatingView: View {
    @ObservedObject var store: ScientificCalculatorStore
    let onClose: () -> Void
    let onInsertIntoNote: ((String) -> Void)?

    @State private var dragCurrent: CGSize = .zero
    @State private var showCopiedToast = false
    @State private var isKeyboardActive = false

    public init(
        store: ScientificCalculatorStore = .shared,
        onClose: @escaping () -> Void,
        onInsertIntoNote: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.onClose = onClose
        self.onInsertIntoNote = onInsertIntoNote
    }

    private var effectiveResult: String {
        if !store.result.isEmpty {
            return store.result
        }
        return store.livePreviewResult
    }

    enum InsertMode {
        case formulaAndResult
        case resultOnly
        case formulaOnly
    }

    private func formattedInsertText(mode: InsertMode) -> String {
        let res = effectiveResult
        switch mode {
        case .formulaAndResult:
            if !res.isEmpty && !store.resultIsError {
                return "\(store.expression) = \(res)"
            } else {
                return store.expression
            }
        case .resultOnly:
            return res.isEmpty ? store.expression : res
        case .formulaOnly:
            return store.expression
        }
    }

    public var body: some View {
        if store.isMinimized {
            minimizedBubble
        } else {
            fullCalculatorWindow
        }
    }

    // MARK: - Minimized Floating Pill

    private var minimizedBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            Text(store.result.isEmpty ? (store.expression.isEmpty ? "Rechner" : store.expression) : "= " + store.result)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.isMinimized = false
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color.teal.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .offset(x: store.dragOffset.width + dragCurrent.width,
                y: store.dragOffset.height + dragCurrent.height)
        .gesture(
            DragGesture()
                .onChanged { v in dragCurrent = v.translation }
                .onEnded { v in
                    store.dragOffset.width += v.translation.width
                    store.dragOffset.height += v.translation.height
                    dragCurrent = .zero
                }
        )
        .padding(20)
    }

    // MARK: - Full Calculator Window

    private var fullCalculatorWindow: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            if store.showHistory {
                historyView
            } else {
                // Expression Display & Result & Insert
                displayView

                Divider()

                // Cursor navigation & edit bar
                cursorToolbar

                Divider()

                // Keypad
                keypadView
            }
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .offset(x: store.dragOffset.width + dragCurrent.width,
                y: store.dragOffset.height + dragCurrent.height)
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text("In Zwischenablage kopiert!")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .offset(y: -35)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(16)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Drag Handle & Title
            HStack(spacing: 6) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.teal)

                Text("Rechner")
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            // DEG / RAD Toggle
            Button {
                store.toggleDegreeMode()
            } label: {
                Text(store.isDegreeMode ? "DEG" : "RAD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(store.isDegreeMode ? .teal : .orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill((store.isDegreeMode ? Color.teal : Color.orange).opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .help(store.isDegreeMode ? "Grad-Modus aktiv (Tippen für Bogenmaß)" : "Bogenmaß aktiv (Tippen für Grad)")

            // History Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.showHistory.toggle()
                }
            } label: {
                Image(systemName: store.showHistory ? "keyboard" : "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(store.showHistory ? .teal : .secondary)
            }
            .buttonStyle(.plain)
            .help(store.showHistory ? "Tastatur anzeigen" : "Verlauf anzeigen")

            // Minimize
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.isMinimized = true
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Minimieren")

            // Close
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Schließen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in dragCurrent = v.translation }
                .onEnded { v in
                    store.dragOffset.width += v.translation.width
                    store.dragOffset.height += v.translation.height
                    dragCurrent = .zero
                }
        )
    }

    // MARK: - Display View (Multi-Line Wrapping, Cursor, Result & Prominent Insert)

    private var displayView: some View {
        VStack(spacing: 6) {
            // Editable Expression Text View
            ZStack(alignment: .topLeading) {
                if store.expression.isEmpty {
                    Text("Formel eingeben...")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                CalculatorExpressionTextView(
                    text: $store.expression,
                    cursorIndex: $store.cursorIndex,
                    isKeyboardActive: isKeyboardActive,
                    onCommit: {
                        store.calculate()
                    }
                )
            }
            .frame(minHeight: 52, maxHeight: 86)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.6))
            .cornerRadius(10)

            // Result Row
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                if !store.result.isEmpty {
                    Text("=")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(store.resultIsError ? .red : .teal)
                    Text(store.result)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(store.resultIsError ? .red : .teal)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                } else if !store.livePreviewResult.isEmpty {
                    Text("=")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(store.livePreviewResult)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(" ")
                        .font(.system(size: 18))
                }

                Spacer()

                if !effectiveResult.isEmpty {
                    Button {
                        UIPasteboard.general.string = effectiveResult
                        withAnimation { showCopiedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showCopiedToast = false }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("Kopieren")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Prominent Insert into Note Bar
            if onInsertIntoNote != nil {
                HStack(spacing: 6) {
                    Button {
                        let text = formattedInsertText(mode: .formulaAndResult)
                        onInsertIntoNote?(text)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Formel mit Ergebnis einfügen")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(store.expression.isEmpty ? Color.gray.opacity(0.4) : Color.teal)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.expression.isEmpty)

                    Menu {
                        Button {
                            let text = formattedInsertText(mode: .formulaAndResult)
                            onInsertIntoNote?(text)
                        } label: {
                            Label("Formel mit Ergebnis (\(formattedInsertText(mode: .formulaAndResult)))", systemImage: "equal")
                        }

                        if !effectiveResult.isEmpty {
                            Button {
                                let text = formattedInsertText(mode: .resultOnly)
                                onInsertIntoNote?(text)
                            } label: {
                                Label("Nur Ergebnis (\(effectiveResult))", systemImage: "number")
                            }
                        }

                        Button {
                            let text = formattedInsertText(mode: .formulaOnly)
                            onInsertIntoNote?(text)
                        } label: {
                            Label("Nur Formel (\(store.expression))", systemImage: "function")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(store.expression.isEmpty ? .secondary.opacity(0.4) : .teal)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .disabled(store.expression.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Cursor Navigation & Edit Toolbar

    private var cursorToolbar: some View {
        HStack(spacing: 5) {
            editToolbarButton(icon: "backward.end.fill", label: "Start") {
                store.moveCursorToStart()
            }

            editToolbarButton(icon: "chevron.left", label: "Links") {
                store.moveCursorLeft()
            }

            editToolbarButton(icon: "chevron.right", label: "Rechts") {
                store.moveCursorRight()
            }

            editToolbarButton(icon: "forward.end.fill", label: "Ende") {
                store.moveCursorToEnd()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            Button {
                isKeyboardActive.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isKeyboardActive ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isKeyboardActive ? "Tastatur weg" : "Tastatur")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(
                    Capsule().fill(isKeyboardActive ? Color.teal.opacity(0.2) : Color.primary.opacity(0.06))
                )
                .foregroundColor(isKeyboardActive ? .teal : .primary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.clear()
            } label: {
                Text("AC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        Capsule().fill(Color.red.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Alles löschen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
    }

    private func editToolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary.opacity(0.85))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Keypad View

    private var keypadView: some View {
        VStack(spacing: 5) {
            // Row 1: 2nd, (, ), 1/x, C, ⌫
            HStack(spacing: 5) {
                calcButton(title: "2nd", color: store.is2ndActive ? .teal : Color(uiColor: .tertiarySystemFill), textColor: store.is2ndActive ? .white : .primary) {
                    store.toggle2nd()
                }
                calcButton(title: "(", color: Color(uiColor: .tertiarySystemFill)) { store.insertToken("(") }
                calcButton(title: ")", color: Color(uiColor: .tertiarySystemFill)) { store.insertToken(")") }
                calcButton(title: store.is2ndActive ? "|x|" : "1/x", color: Color(uiColor: .tertiarySystemFill)) {
                    if store.is2ndActive { store.insertFunction("abs") } else { store.insertToken("1/(") }
                }
                calcButton(title: "C", color: Color.red.opacity(0.18), textColor: .red) { store.clear() }
                calcButton(title: "⌫", color: Color.orange.opacity(0.18), textColor: .orange) { store.backspace() }
            }

            // Row 2: Trig & Powers, ÷
            HStack(spacing: 5) {
                calcButton(title: store.is2ndActive ? "sin⁻¹" : "sin", color: Color(uiColor: .tertiarySystemFill)) {
                    store.insertFunction(store.is2ndActive ? "arcsin" : "sin")
                }
                calcButton(title: store.is2ndActive ? "cos⁻¹" : "cos", color: Color(uiColor: .tertiarySystemFill)) {
                    store.insertFunction(store.is2ndActive ? "arccos" : "cos")
                }
                calcButton(title: store.is2ndActive ? "tan⁻¹" : "tan", color: Color(uiColor: .tertiarySystemFill)) {
                    store.insertFunction(store.is2ndActive ? "arctan" : "tan")
                }
                calcButton(title: store.is2ndActive ? "x³" : "x²", color: Color(uiColor: .tertiarySystemFill)) {
                    store.insertToken(store.is2ndActive ? "³" : "²")
                }
                calcButton(title: store.is2ndActive ? "³√" : "√", color: Color(uiColor: .tertiarySystemFill)) {
                    store.insertFunction(store.is2ndActive ? "cbrt" : "sqrt")
                }
                calcButton(title: "÷", color: Color.teal.opacity(0.25), textColor: .teal) { store.insertToken(" ÷ ") }
            }

            // Row 3: ln, log, 7, 8, 9, ×
            HStack(spacing: 5) {
                calcButton(title: "ln", color: Color(uiColor: .tertiarySystemFill)) { store.insertFunction("ln") }
                calcButton(title: "log", color: Color(uiColor: .tertiarySystemFill)) { store.insertFunction("log10") }
                calcButton(title: "7", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("7") }
                calcButton(title: "8", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("8") }
                calcButton(title: "9", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("9") }
                calcButton(title: "×", color: Color.teal.opacity(0.25), textColor: .teal) { store.insertToken(" × ") }
            }

            // Row 4: π, e, 4, 5, 6, −
            HStack(spacing: 5) {
                calcButton(title: "π", color: Color(uiColor: .tertiarySystemFill)) { store.insertToken("π") }
                calcButton(title: "e", color: Color(uiColor: .tertiarySystemFill)) { store.insertToken("e") }
                calcButton(title: "4", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("4") }
                calcButton(title: "5", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("5") }
                calcButton(title: "6", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("6") }
                calcButton(title: "−", color: Color.teal.opacity(0.25), textColor: .teal) { store.insertToken(" − ") }
            }

            // Row 5: ^, %, 1, 2, 3, +
            HStack(spacing: 5) {
                calcButton(title: "^", color: Color(uiColor: .tertiarySystemFill)) { store.insertToken("^") }
                calcButton(title: store.is2ndActive ? "x!" : "%", color: Color(uiColor: .tertiarySystemFill)) {
                    if store.is2ndActive { store.insertFunction("fact") } else { store.insertToken("%") }
                }
                calcButton(title: "1", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("1") }
                calcButton(title: "2", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("2") }
                calcButton(title: "3", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("3") }
                calcButton(title: "+", color: Color.teal.opacity(0.25), textColor: .teal) { store.insertToken(" + ") }
            }

            // Row 6: Ans, ±, 0, ,, =
            HStack(spacing: 5) {
                calcButton(title: "Ans", color: Color(uiColor: .tertiarySystemFill), textColor: .teal) { store.insertAns() }
                calcButton(title: "±", color: Color(uiColor: .tertiarySystemFill)) { store.toggleSign() }
                calcButton(title: "0", color: Color(uiColor: .secondarySystemFill)) { store.insertToken("0") }
                calcButton(title: ",", color: Color(uiColor: .secondarySystemFill)) { store.insertToken(",") }
                // Equals Button (spans 2 columns width)
                Button {
                    store.calculate()
                } label: {
                    Text("=")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.teal)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 108)
            }
        }
        .padding(10)
    }

    private func calcButton(
        title: String,
        color: Color,
        textColor: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - History View

    private var historyView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Berechnungsverlauf")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                Spacer()
                if !store.history.isEmpty {
                    Button("Leeren") {
                        store.clearHistory()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if store.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Noch keine Rechnungen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.history) { entry in
                            Button {
                                store.restoreHistoryEntry(entry)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.expression)
                                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text("= \(entry.result)")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundColor(.teal)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

