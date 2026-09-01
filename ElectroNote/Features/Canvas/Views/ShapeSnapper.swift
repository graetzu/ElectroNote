import UIKit
import PencilKit

// MARK: - Shape Snapper
// Analyses a just-committed PKStroke and replaces it with a clean
// geometric version if it clearly looks like a line, circle, or rectangle.

enum SnappedShape { case line, circle, rect }

struct ShapeSnapper {

    // MARK: - Public entry point

    /// Returns a clean replacement stroke, or nil if the stroke doesn't
    /// clearly match a geometric shape.
    static func snap(_ stroke: PKStroke) -> (PKStroke, SnappedShape)? {
        let pts = Array(stroke.path).map { $0.location }
        guard pts.count >= 4 else { return nil }

        let bounds = stroke.renderBounds
        let diag   = hypot(bounds.width, bounds.height)
        guard diag > 20 else { return nil }

        if let s = tryLine(stroke, pts: pts, diag: diag)   { return (s, .line)   }
        if let s = tryCircle(stroke, pts: pts)              { return (s, .circle) }
        if let s = tryRect(stroke, pts: pts, bounds: bounds){ return (s, .rect)   }
        return nil
    }

    // MARK: - Line

    private static func tryLine(_ stroke: PKStroke, pts: [CGPoint], diag: CGFloat) -> PKStroke? {
        guard let a = pts.first, let b = pts.last else { return nil }
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 20 else { return nil }

        let maxDev = pts.map { perpDist($0, a: a, b: b) }.max() ?? 0
        guard maxDev / len < 0.09 else { return nil }

        return makeStroke([a, b], like: stroke)
    }

    // MARK: - Circle / Ellipse

    private static func tryCircle(_ stroke: PKStroke, pts: [CGPoint]) -> PKStroke? {
        guard let first = pts.first, let last = pts.last else { return nil }

        // Centroid
        let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)

        // Stroke must close (end ≈ start)
        let avgR = pts.map { hypot($0.x - cx, $0.y - cy) }.reduce(0, +) / CGFloat(pts.count)
        guard avgR > 10 else { return nil }
        let gap  = hypot(last.x - first.x, last.y - first.y)
        guard gap < avgR * 0.7 else { return nil }

        // All points equidistant from centroid
        let dists  = pts.map { hypot($0.x - cx, $0.y - cy) }
        let maxDev = dists.map { abs($0 - avgR) }.max() ?? 0
        guard maxDev / avgR < 0.18 else { return nil }

        let circlePts = (0...64).map { i -> CGPoint in
            let angle = CGFloat(i) / 64.0 * 2 * .pi
            return CGPoint(x: cx + avgR * cos(angle), y: cy + avgR * sin(angle))
        }
        return makeStroke(circlePts, like: stroke)
    }

    // MARK: - Rectangle

    private static func tryRect(_ stroke: PKStroke, pts: [CGPoint], bounds: CGRect) -> PKStroke? {
        guard let first = pts.first, let last = pts.last else { return nil }
        guard bounds.width > 20, bounds.height > 20 else { return nil }

        // Must be a closed shape
        let diag = hypot(bounds.width, bounds.height)
        let gap  = hypot(last.x - first.x, last.y - first.y)
        guard gap < diag * 0.28 else { return nil }

        // Exactly 3–5 corners (direction changes > 45°)
        let corners = findCorners(pts)
        guard (3...5).contains(corners.count) else { return nil }

        let r = bounds
        let rectPts: [CGPoint] = [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.minX, y: r.minY)
        ]
        return makeStroke(rectPts, like: stroke)
    }

    // MARK: - Corner detection

    private static func findCorners(_ pts: [CGPoint]) -> [Int] {
        let step = max(1, pts.count / 50)
        var raw: [Int] = []
        for i in stride(from: step, to: pts.count - step, by: step) {
            let v1 = CGPoint(x: pts[i].x - pts[i-step].x, y: pts[i].y - pts[i-step].y)
            let v2 = CGPoint(x: pts[i+step].x - pts[i].x, y: pts[i+step].y - pts[i].y)
            let dot   = v1.x*v2.x + v1.y*v2.y
            let cross = abs(v1.x*v2.y - v1.y*v2.x)
            if atan2(cross, dot) > .pi / 4 { raw.append(i) }
        }
        // Merge nearby corners
        var merged: [Int] = []
        for c in raw {
            if merged.isEmpty || c - merged.last! > pts.count / 10 { merged.append(c) }
        }
        return merged
    }

    // MARK: - Geometry helpers

    private static func perpDist(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    // MARK: - Stroke builder

    private static func makeStroke(_ pts: [CGPoint], like src: PKStroke) -> PKStroke {
        let n = src.path.count
        let avgForce   = (0..<n).map { src.path[$0].force      }.reduce(0,+) / CGFloat(n)
        let avgWidth   = (0..<n).map { src.path[$0].size.width }.reduce(0,+) / CGFloat(n)
        let avgAzimuth = (0..<n).map { src.path[$0].azimuth    }.reduce(0,+) / CGFloat(n)
        let avgAlt     = (0..<n).map { src.path[$0].altitude   }.reduce(0,+) / CGFloat(n)
        let sz = CGSize(width: avgWidth, height: avgWidth)

        let sPts: [PKStrokePoint] = pts.enumerated().map { i, pt in
            PKStrokePoint(location: pt,
                          timeOffset: TimeInterval(i) * 0.01,
                          size: sz, opacity: 1,
                          force: avgForce,
                          azimuth: avgAzimuth,
                          altitude: avgAlt)
        }
        return PKStroke(ink: src.ink,
                        path: PKStrokePath(controlPoints: sPts, creationDate: Date()))
    }
}
