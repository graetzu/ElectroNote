import SwiftUI

// Sheet that lets the user configure a plot and insert it into the notebook as an image.

struct PlotInserterView: View {
    @StateObject private var vm = PlotInserterViewModel()
    let onInsert: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // f(x) input row
                HStack(spacing: 10) {
                    Text("f(x) =").foregroundStyle(.secondary).font(.title3.monospaced())
                    TextField("x^2 - 3*x + 1", text: $vm.expression)
                        .font(.title3.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { vm.compute() }
                    Button { vm.compute() } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                // x-range row
                HStack(spacing: 16) {
                    labeledField("x min", value: $vm.xMin)
                    labeledField("x max", value: $vm.xMax)
                    Spacer()
                    Button("Plot") { vm.compute() }.buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                // Plot preview
                if !vm.plotPoints.isEmpty {
                    FunctionPlotView(points:  vm.plotPoints,
                                     xMin:    vm.xMin,
                                     xMax:    vm.xMax,
                                     yRange:  vm.yRange)
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
            .navigationTitle("Funktion einfügen")
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
                    .disabled(vm.plotPoints.isEmpty)
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
                .frame(width: 80)
        }
    }
}

// MARK: - PlotInserterViewModel

@MainActor
private final class PlotInserterViewModel: ObservableObject {
    @Published var expression = "x^2"
    @Published var xMin: Double = -5
    @Published var xMax: Double =  5
    @Published var plotPoints: [MathViewModel.PlotPoint] = []
    @Published var yRange: ClosedRange<Double> = -10...10

    private let evaluator = MathEvaluator()

    func compute() {
        guard xMin < xMax else { return }
        var pts: [MathViewModel.PlotPoint] = []
        var yMin = Double.infinity, yMax = -Double.infinity
        for i in 0...600 {
            let x = xMin + (xMax - xMin) * Double(i) / 600
            if let y = evaluator.evaluateFunction(expression, at: x) {
                pts.append(.init(x: x, y: y))
                yMin = min(yMin, y); yMax = max(yMax, y)
            }
        }
        plotPoints = pts
        if pts.count > 1, yMin < yMax {
            let m = (yMax - yMin) * 0.12
            yRange = (yMin - m)...(yMax + m)
        } else {
            yRange = -10...10
        }
    }

    func renderToImage() -> UIImage? {
        guard !plotPoints.isEmpty else { return nil }
        let plotView = FunctionPlotView(points:  plotPoints,
                                        xMin:    xMin,
                                        xMax:    xMax,
                                        yRange:  yRange)
            .frame(width: 480, height: 320)
            .padding(16)
            .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: plotView)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
