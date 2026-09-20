import JavaScriptCore

// Evaluates mathematical expressions via JavaScriptCore.
// Supports: +−×÷^, sin/cos/tan, sqrt, log/ln, π, ², ³
final class MathEvaluator {

    private let ctx = JSContext()!

    init() {
        ctx.evaluateScript("""
            function sin_deg(x) { return Math.sin(x * Math.PI / 180); }
            function cos_deg(x) { return Math.cos(x * Math.PI / 180); }
            function tan_deg(x) { return Math.tan(x * Math.PI / 180); }
            function asin_deg(x) { return Math.asin(x) * 180 / Math.PI; }
            function acos_deg(x) { return Math.acos(x) * 180 / Math.PI; }
            function atan_deg(x) { return Math.atan(x) * 180 / Math.PI; }
            function fact(n) {
                if (n < 0) return NaN;
                n = Math.round(n);
                if (n <= 1) return 1;
                var r = 1;
                for (var i = 2; i <= n; i++) r *= i;
                return r;
            }
        """)
    }

    // MARK: - Scalar evaluation

    func evaluate(_ raw: String, isDegreeMode: Bool = false) -> Result<Double, MathError> {
        let script = sanitize(raw, isDegreeMode: isDegreeMode)
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

    func evaluateFunction(_ raw: String, at x: Double, isDegreeMode: Bool = false) -> Double? {
        let script = sanitize(raw, isDegreeMode: isDegreeMode)
        guard !script.isEmpty else { return nil }
        let fullScript = "var x=\(x); \(script)"
        guard let value = ctx.evaluateScript(fullScript),
              !value.isUndefined, !value.isNull else { return nil }
        let d = value.toDouble()
        return (d.isNaN || d.isInfinite) ? nil : d
    }

    // MARK: - Sanitisation

    func sanitize(_ raw: String, isDegreeMode: Bool = false) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("=") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty else { return "" }

        // Decimal comma (e.g. 3,5 + 2 -> 3.5 + 2)
        s = s.replacingOccurrences(of: ",", with: ".")

        // Functions – longest matches first to avoid partial replacement
        let fnMap: [(String, String)] = isDegreeMode ? [
            ("sqrt(",   "Math.sqrt("),
            ("cbrt(",   "Math.cbrt("),
            ("³√(",     "Math.cbrt("),
            ("√(",      "Math.sqrt("),
            ("fact(",   "fact("),
            ("arcsin(", "asin_deg("),
            ("arccos(", "acos_deg("),
            ("arctan(", "atan_deg("),
            ("asin(",   "asin_deg("),
            ("acos(",   "acos_deg("),
            ("atan(",   "atan_deg("),
            ("sin(",    "sin_deg("),
            ("cos(",    "cos_deg("),
            ("tan(",    "tan_deg("),
            ("log10(",  "Math.log10("),
            ("log2(",   "Math.log2("),
            ("log(",    "Math.log10("),
            ("ln(",     "Math.log("),
            ("exp(",    "Math.exp("),
            ("abs(",    "Math.abs("),
        ] : [
            ("sqrt(",   "Math.sqrt("),
            ("cbrt(",   "Math.cbrt("),
            ("³√(",     "Math.cbrt("),
            ("√(",      "Math.sqrt("),
            ("fact(",   "fact("),
            ("arcsin(", "Math.asin("),
            ("arccos(", "Math.acos("),
            ("arctan(", "Math.atan("),
            ("asin(",   "Math.asin("),
            ("acos(",   "Math.acos("),
            ("atan(",   "Math.atan("),
            ("sin(",    "Math.sin("),
            ("cos(",    "Math.cos("),
            ("tan(",    "Math.tan("),
            ("log10(",  "Math.log10("),
            ("log2(",   "Math.log2("),
            ("log(",    "Math.log10("),
            ("ln(",     "Math.log("),
            ("exp(",    "Math.exp("),
            ("abs(",    "Math.abs("),
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

        // euler constant (careful not to replace in function names)
        s = s.replacingOccurrences(of: " e ", with: " Math.E ")
        if s.hasPrefix("e ") || s.hasPrefix("e+") || s.hasPrefix("e-") || s.hasPrefix("e*") || s.hasPrefix("e/") {
            s = "Math.E" + s.dropFirst()
        }
        if s.hasSuffix(" e") || s.hasSuffix("+e") || s.hasSuffix("-e") || s.hasSuffix("*e") || s.hasSuffix("/e") {
            s = String(s.dropLast()) + "Math.E"
        }
        if s == "e" {
            s = "Math.E"
        }

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
