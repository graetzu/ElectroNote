import SwiftUI

// MARK: - FunctionEntry

struct FunctionEntry: Identifiable {
    let id = UUID()
    var expression: String
    var color: Color
}

// MARK: - PlotInserterView

struct PlotInserterView: View {
    @StateObject private var vm = PlotInserterViewModel()
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Function rows
                ForEach($vm.functions) { $fn in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(fn.color)
                            .frame(width: 12, height: 12)
                        Text("f(x) =")
                            .foregroundStyle(.secondary)
                            .font(.title3.monospaced())
                        TextField("Ausdruck …", text: $fn.expression)
                            .font(.title3.monospaced())
                            .autocorrectionDisabled()
                            .onSubmit { vm.compute() }
                        if vm.functions.count > 1 {
                            Button {
                                vm.remove(id: fn.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    Divider().padding(.leading)
                }

                // Controls row
                HStack(spacing: 14) {
                    Button {
                        vm.addFunction()
                    } label: {
                        Label("Funktion", systemImage: "plus.circle")
                    }
                    .disabled(vm.functions.count >= 5)

                    Spacer()

                    labeledField("x min", value: $vm.xMin)
                    labeledField("x max", value: $vm.xMax)

                    Button("Plot") { vm.compute() }
                        .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                // Plot preview
                if !vm.curves.isEmpty {
                    FunctionPlotView(curves: vm.curves,
                                     xMin: vm.xMin, xMax: vm.xMax, yRange: vm.yRange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .padding()
                } else {
                    ContentUnavailableView("Noch kein Graph",
                                           systemImage: "waveform.path",
                                           description: Text("Funktion eingeben und Plot tippen."))
                        .frame(height: 300)
                }
            }
            .navigationTitle("Funktionen einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einfügen") {
                        if let img = vm.renderToImage() {
                            onInsert(img)
                            dismiss()
                        }
                    }
                    .disabled(vm.curves.isEmpty)
                    .bold()
                }
            }
            .onAppear { vm.compute() }
        }
    }

    private func labeledField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
        }
    }
}

// MARK: - PlotInserterViewModel

@MainActor
private final class PlotInserterViewModel: ObservableObject {
    @Published var functions: [FunctionEntry] = [FunctionEntry(expression: "x^2", color: .blue)]
    @Published var xMin: Double = -5
    @Published var xMax: Double =  5
    @Published var curves: [FunctionPlotView.Curve] = []
    @Published var yRange: ClosedRange<Double> = -10...10

    private let palette: [Color] = [.blue, .red, .green, .orange, .purple]
    private let evaluator = MathEvaluator()

    func addFunction() {
        let color = palette[functions.count % palette.count]
        functions.append(FunctionEntry(expression: "", color: color))
    }

    func remove(id: UUID) {
        functions.removeAll { $0.id == id }
        if functions.isEmpty {
            functions = [FunctionEntry(expression: "x^2", color: .blue)]
        }
        compute()
    }

    func compute() {
        guard xMin < xMax else { return }
        var allCurves: [FunctionPlotView.Curve] = []
        var globalYMin = Double.infinity, globalYMax = -Double.infinity

        for fn in functions {
            guard !fn.expression.isEmpty else { continue }
            var pts: [MathViewModel.PlotPoint] = []
            for i in 0...600 {
                let x = xMin + (xMax - xMin) * Double(i) / 600
                if let y = evaluator.evaluateFunction(fn.expression, at: x) {
                    pts.append(.init(x: x, y: y))
                    globalYMin = min(globalYMin, y)
                    globalYMax = max(globalYMax, y)
                }
            }
            if !pts.isEmpty {
                allCurves.append(.init(points: pts, color: fn.color, label: fn.expression))
            }
        }

        curves = allCurves
        if globalYMin < globalYMax {
            let m = (globalYMax - globalYMin) * 0.12
            yRange = (globalYMin - m)...(globalYMax + m)
        } else {
            yRange = -10...10
        }
    }

    func renderToImage() -> UIImage? {
        guard !curves.isEmpty else { return nil }
        let plotView = FunctionPlotView(curves: curves, xMin: xMin, xMax: xMax, yRange: yRange)
            .frame(width: 540, height: curves.count > 1 ? 380 : 340)
            .padding(16)
            .background(Color(.systemBackground))
        let renderer = ImageRenderer(content: plotView)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
