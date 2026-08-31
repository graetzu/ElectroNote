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
