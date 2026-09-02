import JavaScriptCore

// Evaluates mathematical expressions via JavaScriptCore.
// Supports: +−×÷^, sin/cos/tan, sqrt, log/ln, π, ², ³
final class MathEvaluator {

    private let ctx = JSContext()!

    // MARK: - Scalar evaluation

    func evaluate(_ raw: String) -> Result<Double, MathError> {
        let script = sanitize(raw)
        guard !script.isEmpty else { return .failure(.emptyExpression) }

        guard let value = ctx.evaluateScript(script),
              !value.isUndefined, !value.isNull else {
            return .failure(.evaluationFailed)
        }
        let d = value.toDouble()
        if d.isNaN      { return .failure(.evaluationFailed) }
        if d.isInfinite { return .failure(.divisionByZero) }

        // Round to avoid floating-point noise (e.g. 0.30000000000000004)
        let rounded = (d * 1e10).rounded() / 1e10
        return .success(rounded)
    }

    // MARK: - Function evaluation  f(x)

    func evaluateFunction(_ raw: String, at x: Double) -> Double? {
        let script = sanitize(raw)
        guard !script.isEmpty else { return nil }
        let fullScript = "var x=\(x); \(script)"
        guard let value = ctx.evaluateScript(fullScript),
              !value.isUndefined, !value.isNull else { return nil }
        let d = value.toDouble()
        return (d.isNaN || d.isInfinite) ? nil : d
    }

    // MARK: - Sanitisation

    func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("=") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty else { return "" }

        // Decimal comma (e.g. 3,5 + 2 -> 3.5 + 2)
        s = s.replacingOccurrences(of: ",", with: ".")

        // Functions – longest matches first to avoid partial replacement
        let fnMap: [(String, String)] = [
            ("sqrt(",  "Math.sqrt("),
            ("arcsin(","Math.asin("),
            ("arccos(","Math.acos("),
            ("arctan(","Math.atan("),
            ("sin(",   "Math.sin("),
            ("cos(",   "Math.cos("),
            ("tan(",   "Math.tan("),
            ("log10(", "Math.log10("),
            ("log2(",  "Math.log2("),
            ("log(",   "Math.log10("),
            ("ln(",    "Math.log("),
            ("exp(",   "Math.exp("),
            ("abs(",   "Math.abs("),
        ]
        for (from, to) in fnMap {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // Constants & symbols
        s = s.replacingOccurrences(of: "π", with: "Math.PI")
        s = s.replacingOccurrences(of: "pi", with: "Math.PI")
        s = s.replacingOccurrences(of: "Ω", with: "")     // strip unit symbols
        s = s.replacingOccurrences(of: "²", with: "**2")
        s = s.replacingOccurrences(of: "³", with: "**3")

        // Operators
        s = s.replacingOccurrences(of: "^",  with: "**")
        s = s.replacingOccurrences(of: "×",  with: "*")
        s = s.replacingOccurrences(of: "·",  with: "*")
        s = s.replacingOccurrences(of: " x ", with: " * ")
        s = s.replacingOccurrences(of: " X ", with: " * ")
        s = s.replacingOccurrences(of: "÷",  with: "/")
        s = s.replacingOccurrences(of: ":",  with: "/")
        s = s.replacingOccurrences(of: "−",  with: "-")  // Unicode minus

        return s
    }
}

enum MathError: LocalizedError {
    case emptyExpression, evaluationFailed, divisionByZero

    var errorDescription: String? {
        switch self {
        case .emptyExpression:  return "Kein Ausdruck eingegeben."
        case .evaluationFailed: return "Ausdruck konnte nicht berechnet werden."
        case .divisionByZero:   return "Division durch Null."
        }
    }
}
