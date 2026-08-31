import SwiftUI

struct FunctionPlotView: View {
    let points: [MathViewModel.PlotPoint]
    let xMin: Double
    let xMax: Double
    let yRange: ClosedRange<Double>

    var body: some View {
        Canvas { ctx, size in
            let c = PlotCoords(size: size, xMin: xMin, xMax: xMax,
                               yMin: yRange.lowerBound, yMax: yRange.upperBound)
            drawGrid(ctx, c)
            drawAxes(ctx, c)
            drawCurve(ctx, c)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Grid

    private func drawGrid(_ ctx: GraphicsContext, _ c: PlotCoords) {
        let style = StrokeStyle(lineWidth: 0.5)
        for tick in c.xTicks {
            var p = Path()
            p.move(to:    CGPoint(x: c.sx(tick), y: 0))
            p.addLine(to: CGPoint(x: c.sx(tick), y: c.size.height))
            ctx.stroke(p, with: .color(.gray.opacity(0.25)), style: style)
        }
        for tick in c.yTicks {
            var p = Path()
            p.move(to:    CGPoint(x: 0,          y: c.sy(tick)))
            p.addLine(to: CGPoint(x: c.size.width, y: c.sy(tick)))
            ctx.stroke(p, with: .color(.gray.opacity(0.25)), style: style)
        }
    }

    // MARK: - Axes + labels

    private func drawAxes(_ ctx: GraphicsContext, _ c: PlotCoords) {
        let thick = StrokeStyle(lineWidth: 1.5)

        // x-axis
        let y0 = c.sy(0).clamped(to: 0...c.size.height)
        var xa = Path()
        xa.move(to: CGPoint(x: 0, y: y0))
        xa.addLine(to: CGPoint(x: c.size.width, y: y0))
        ctx.stroke(xa, with: .color(.primary.opacity(0.6)), style: thick)

        // y-axis
        let x0 = c.sx(0).clamped(to: 0...c.size.width)
        var ya = Path()
        ya.move(to: CGPoint(x: x0, y: 0))
        ya.addLine(to: CGPoint(x: x0, y: c.size.height))
        ctx.stroke(ya, with: .color(.primary.opacity(0.6)), style: thick)

        // Tick labels
        let font = Font.system(size: 9, design: .monospaced)
        for tick in c.xTicks where tick != 0 {
            let label = Text(formatTick(tick)).font(font).foregroundColor(.secondary)
            ctx.draw(label, at: CGPoint(x: c.sx(tick), y: y0 + 10))
        }
        for tick in c.yTicks where tick != 0 {
            let label = Text(formatTick(tick)).font(font).foregroundColor(.secondary)
            ctx.draw(label, at: CGPoint(x: x0 + 14, y: c.sy(tick)))
        }
    }

    // MARK: - Curve

    private func drawCurve(_ ctx: GraphicsContext, _ c: PlotCoords) {
        guard points.count > 1 else { return }

        var path = Path()
        var started = false

        for pt in points {
            let sp = CGPoint(x: c.sx(pt.x), y: c.sy(pt.y))
            // Skip out-of-bounds y to avoid huge jumps (asymptotes)
            if sp.y < -c.size.height || sp.y > c.size.height * 2 {
                started = false
                continue
            }
            if !started { path.move(to: sp); started = true }
            else        { path.addLine(to: sp) }
        }

        ctx.stroke(path, with: .color(.blue), lineWidth: 2.5)
    }

    private func formatTick(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Coordinate helper

private struct PlotCoords {
    let size: CGSize
    let xMin, xMax, yMin, yMax: Double

    func sx(_ x: Double) -> CGFloat {
        CGFloat((x - xMin) / (xMax - xMin)) * size.width
    }
    func sy(_ y: Double) -> CGFloat {
        size.height - CGFloat((y - yMin) / (yMax - yMin)) * size.height
    }

    var xTicks: [Double] { ticks(min: xMin, max: xMax) }
    var yTicks: [Double] { ticks(min: yMin, max: yMax) }

    private func ticks(min: Double, max: Double) -> [Double] {
        let span = max - min
        let raw  = span / 8
        let mag  = pow(10, floor(log10(raw)))
        var step = (raw / mag).rounded() * mag
        if step == 0 { step = 1 }
        let first = ceil(min / step) * step
        var ticks: [Double] = []
        var t = first
        while t <= max + 1e-9 {
            ticks.append(t)
            t += step
        }
        return ticks
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
