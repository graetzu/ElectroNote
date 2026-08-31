import PencilKit
import SwiftUI

@MainActor
final class MathViewModel: ObservableObject {

    // MARK: - Mode

    enum Mode: String, CaseIterable {
        case calculator  = "Rechner"
        case handwriting = "Handschrift"
        case plotter     = "Plotter"
    }

    @Published var mode: Mode = .calculator

    // MARK: - Calculator

    @Published var expression: String = ""
    @Published var result: String = ""
    @Published var resultIsError: Bool = false

    // MARK: - Handwriting

    @Published var drawing = PKDrawing()
    @Published var recognitionState: RecognitionState = .idle
    @Published var recognizedText: String = ""

    enum RecognitionState { case idle, processing, done, failed }

    // MARK: - Plotter

    @Published var functionExpression: String = "x^2"
    @Published var xMin: Double = -10
    @Published var xMax: Double = 10
    @Published var plotPoints: [PlotPoint] = []
    @Published var plotYRange: ClosedRange<Double> = -10...10

    struct PlotPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    // MARK: - Services

    private let evaluator  = MathEvaluator()
    private let recognizer = MathRecognizer()

    // MARK: - Calculator actions

    func evaluateExpression() {
        guard !expression.isEmpty else { result = ""; return }
        switch evaluator.evaluate(expression) {
        case .success(let value):
            result = formatResult(value)
            resultIsError = false
        case .failure(let error):
            result = error.localizedDescription ?? "Fehler"
            resultIsError = true
        }
    }

    func append(_ symbol: String) {
        expression += symbol
        evaluateExpression()
    }

    func clear() {
        expression = ""
        result = ""
        resultIsError = false
    }

    // MARK: - Handwriting actions

    func recogniseHandwriting(canvasSize: CGSize) {
        guard !drawing.strokes.isEmpty else { return }
        recognitionState = .processing
        Task {
            if let text = await recognizer.recognise(drawing: drawing, canvasSize: canvasSize) {
                recognizedText = text
                // Try to evaluate the recognised text immediately
                expression = text
                evaluateExpression()
                recognitionState = .done
            } else {
                recognitionState = .failed
            }
        }
    }

    func clearHandwriting() {
        drawing = PKDrawing()
        recognizedText = ""
        recognitionState = .idle
    }

    // MARK: - Plotter actions

    func computePlot() {
        guard xMin < xMax else { return }
        let steps = 600
        var pts: [PlotPoint] = []
        var yMin =  Double.infinity
        var yMax = -Double.infinity

        for i in 0...steps {
            let x = xMin + (xMax - xMin) * Double(i) / Double(steps)
            if let y = evaluator.evaluateFunction(functionExpression, at: x) {
                pts.append(PlotPoint(x: x, y: y))
                yMin = min(yMin, y)
                yMax = max(yMax, y)
            }
        }

        plotPoints = pts

        if pts.count > 1, yMin < yMax {
            let margin = (yMax - yMin) * 0.12
            plotYRange = (yMin - margin)...(yMax + margin)
        } else {
            plotYRange = -10...10
        }
    }

    // MARK: - Helpers

    private func formatResult(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e12 {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}
