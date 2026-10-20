import UIKit
import PencilKit

// MARK: - Snapped Shape Types

enum SnappedShape: String {
    case line
    case arrow
    case triangle
    case rect
    case circle
    case ellipse
    case polygon
}

// MARK: - Draw & Hold Gesture Recognizer

/// Passively observes single-finger / Apple Pencil drawing touches on a `PKCanvasView`
/// without interfering with PencilKit's own drawing recognizer.
/// When the user draws a stroke and holds the pen stationary at the end for ~0.38s,
/// `onHoldTriggered` fires so the controller can immediately commit and snap the stroke.
final class DrawAndHoldGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {

    var onHoldTriggered: (() -> Void)?
    var holdDuration: TimeInterval = 0.38
    var movementTolerance: CGFloat = 4.5
    var minimumPathLength: CGFloat = 24.0

    private var startLocation: CGPoint = .zero
    private var lastLocation: CGPoint = .zero
    private var totalDistance: CGFloat = 0
    private var holdTimer: Timer?
    private var didTriggerHoldForCurrentStroke = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func attach(to canvasView: PKCanvasView, onHold: @escaping () -> Void) {
        self.onHoldTriggered = onHold
        canvasView.addGestureRecognizer(self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first else {
            cancelHoldTimer()
            state = .failed
            return
        }
        let loc = touch.location(in: view)
        startLocation = loc
        lastLocation = loc
        totalDistance = 0
        didTriggerHoldForCurrentStroke = false
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard !didTriggerHoldForCurrentStroke, let touch = touches.first else { return }
        let loc = touch.location(in: view)
        let step = hypot(loc.x - lastLocation.x, loc.y - lastLocation.y)

        if step > movementTolerance {
            totalDistance += step
            lastLocation = loc
            if totalDistance >= minimumPathLength {
                restartHoldTimer()
            }
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        cancelHoldTimer()
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        cancelHoldTimer()
        state = .cancelled
    }

    override func reset() {
        super.reset()
        cancelHoldTimer()
        totalDistance = 0
        didTriggerHoldForCurrentStroke = false
    }

    private func restartHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            guard let self, !self.didTriggerHoldForCurrentStroke else { return }
            self.didTriggerHoldForCurrentStroke = true
            self.onHoldTriggered?()
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    // MARK: - UIGestureRecognizerDelegate & Non-interference

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Shape Snapper

struct ShapeSnapper {

    // MARK: - Public Entry Point

    /// Inspects the `PKStrokePoint.timeOffset` values at the tail of a stroke to detect
    /// whether the user paused/held the pen stationary at the end before lifting.
    static func didHoldAtEnd(of stroke: PKStroke) -> Bool {
        let path = stroke.path
        let count = path.count
        guard count >= 5 else { return false }

        let lastPt = path[count - 1]
        let totalDuration = lastPt.timeOffset - path[0].timeOffset
        guard totalDuration >= 0.28 else { return false }

        // Walk backward from the end while points remain within 9 pt of the final point
        var earliestStationaryTime = lastPt.timeOffset
        for i in stride(from: count - 2, through: 0, by: -1) {
            let p = path[i]
            let dist = hypot(p.location.x - lastPt.location.x, p.location.y - lastPt.location.y)
            if dist <= 9.0 {
                earliestStationaryTime = p.timeOffset
            } else {
                break
            }
        }

        let stationaryDuration = lastPt.timeOffset - earliestStationaryTime
        return stationaryDuration >= 0.18
    }

    /// Returns a clean replacement stroke and its shape classification, or `nil`
    /// if the stroke doesn't match a geometric shape.
    /// - Parameters:
    ///   - stroke: The just-committed user stroke.
    ///   - isHoldTriggered: `true` when triggered by Draw & Hold or explicit Shape Mode.
    static func snap(_ stroke: PKStroke, isHoldTriggered: Bool = true) -> (PKStroke, SnappedShape)? {
        let rawPts = Array(stroke.path).map { $0.location }
        let pts = preprocessPoints(rawPts)
        guard pts.count >= 4 else { return nil }

        let bounds = boundingBox(of: pts)
        let diag = hypot(bounds.width, bounds.height)
        guard diag > 18 else { return nil }

        // 1. Straight line
        if let lineStroke = tryLine(stroke, pts: pts, diag: diag, relaxed: isHoldTriggered) {
            return (lineStroke, .line)
        }

        // 2. Single-stroke arrow (shaft + V-tip at end)
        if let arrowStroke = trySingleStrokeArrow(stroke, pts: pts, diag: diag, relaxed: isHoldTriggered) {
            return (arrowStroke, .arrow)
        }

        // 3. Closed shapes (Triangle, Rectangle/Square/Diamond, Circle, Ellipse)
        let perim = polylineLength(pts)
        guard let first = pts.first, let last = pts.last else { return nil }
        let rawGap = hypot(last.x - first.x, last.y - first.y)

        // Trim slight overdraw if the stroke closes and keeps going along the start
        let closedPts = trimClosedLoopOverlap(pts, diag: diag)
        let closedGap = hypot((closedPts.last ?? last).x - first.x, (closedPts.last ?? last).y - first.y)

        let maxAllowedGap = max(diag * (isHoldTriggered ? 0.42 : 0.30), perim * 0.18)
        let isClosed = (min(rawGap, closedGap) <= maxAllowedGap) && (perim > diag * 1.55)

        if isClosed {
            let polyCandidate = fitClosedPolygon(closedPts, bounds: bounds, diag: diag, relaxed: isHoldTriggered)
            let ellipseCandidate = fitCircleOrEllipse(closedPts, bounds: bounds, diag: diag, relaxed: isHoldTriggered)

            switch (polyCandidate, ellipseCandidate) {
            case let (.some(poly), .some(ell)):
                // Pick whichever model better explains the stroke points.
                // Give a slight preference to clean 3/4-corner polygons when errors are close,
                // because hand-drawn squares/triangles with slightly rounded corners can also partially fit an ellipse.
                if poly.corners.count <= 4 && poly.normalizedError <= ell.normalizedError * 1.22 {
                    return (makePolygonStroke(poly.corners, closed: true, like: stroke), poly.shape)
                } else if ell.normalizedError < poly.normalizedError {
                    return (makeCurveStroke(ell.points, like: stroke), ell.shape)
                } else {
                    return (makePolygonStroke(poly.corners, closed: true, like: stroke), poly.shape)
                }

            case let (.some(poly), .none):
                return (makePolygonStroke(poly.corners, closed: true, like: stroke), poly.shape)

            case let (.none, .some(ell)):
                return (makeCurveStroke(ell.points, like: stroke), ell.shape)

            case (.none, .none):
                break
            }
        }

        // 4. Open 3-segment rectangle or 2-segment L/triangle when Hold was explicitly triggered
        if isHoldTriggered, rawGap <= diag * 0.55, perim > diag * 1.45 {
            if let poly = fitClosedPolygon(closedPts, bounds: bounds, diag: diag, relaxed: true) {
                return (makePolygonStroke(poly.corners, closed: true, like: stroke), poly.shape)
            }
        }

        return nil
    }

    // MARK: - Preprocessing

    /// Removes stationary tail jitter (from holding the pen at the end) and deduplicates micro-steps.
    private static func preprocessPoints(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count >= 4 else { return pts }

        // Trim tail cluster where the pen was held still
        var endIdx = pts.count - 1
        let tailAnchor = pts[endIdx]
        while endIdx > 3 && hypot(pts[endIdx - 1].x - tailAnchor.x, pts[endIdx - 1].y - tailAnchor.y) < 3.0 {
            endIdx -= 1
        }

        // Trim start cluster
        var startIdx = 0
        let headAnchor = pts[0]
        while startIdx < endIdx - 3 && hypot(pts[startIdx + 1].x - headAnchor.x, pts[startIdx + 1].y - headAnchor.y) < 2.5 {
            startIdx += 1
        }

        var filtered: [CGPoint] = [pts[startIdx]]
        for i in (startIdx + 1)...endIdx {
            let p = pts[i]
            if hypot(p.x - filtered.last!.x, p.y - filtered.last!.y) >= 1.5 || i == endIdx {
                filtered.append(p)
            }
        }
        return filtered
    }

    /// When a user draws a circle or rectangle in one loop, they often overlap the start by 5-15%
    /// or leave a tiny tail after passing the start point. This trims the loop at its closest approach to `pts[0]`.
    private static func trimClosedLoopOverlap(_ pts: [CGPoint], diag: CGFloat) -> [CGPoint] {
        guard pts.count >= 12, let start = pts.first else { return pts }
        let searchStart = Int(Double(pts.count) * 0.72)
        guard searchStart < pts.count else { return pts }

        var bestIdx = pts.count - 1
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in searchStart..<pts.count {
            let d = hypot(pts[i].x - start.x, pts[i].y - start.y)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }

        if bestDist < diag * 0.25 && bestIdx < pts.count - 1 {
            return Array(pts[0...bestIdx])
        }
        return pts
    }

    // MARK: - 1. Line Recognition

    private static func tryLine(_ stroke: PKStroke, pts: [CGPoint], diag: CGFloat, relaxed: Bool) -> PKStroke? {
        guard let a = pts.first, let b = pts.last else { return nil }
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 18 else { return nil }

        let pathLen = polylineLength(pts)
        // A straight line cannot have a path length much longer than the chord length
        guard pathLen / len < (relaxed ? 1.16 : 1.10) else { return nil }

        let maxDev = pts.map { perpDist($0, a: a, b: b) }.max() ?? 0
        guard maxDev / len < (relaxed ? 0.11 : 0.075) else { return nil }

        let snappedEnd = snapEndpointAngle(from: a, to: b, toleranceDegrees: 5.5)
        return makePolygonStroke([a, snappedEnd], closed: false, like: stroke)
    }

    // MARK: - 2. Single-Stroke Arrow Recognition

    private static func trySingleStrokeArrow(_ stroke: PKStroke, pts: [CGPoint], diag: CGFloat, relaxed: Bool) -> PKStroke? {
        guard pts.count >= 8, let start = pts.first, let end = pts.last else { return nil }

        // Find the point farthest from `start` — candidate arrowhead tip
        var peakIdx = 0
        var maxDist: CGFloat = 0
        for (i, p) in pts.enumerated() {
            let d = hypot(p.x - start.x, p.y - start.y)
            if d > maxDist {
                maxDist = d
                peakIdx = i
            }
        }

        // The peak must be near the latter part of the stroke (65%...94% of points), not the very last point
        guard maxDist > 35,
              peakIdx >= Int(Double(pts.count) * 0.55),
              peakIdx <= pts.count - 3 else { return nil }

        let peak = pts[peakIdx]
        let shaftPts = Array(pts[0...peakIdx])
        let shaftPathLen = polylineLength(shaftPts)
        guard shaftPathLen / maxDist < 1.15 else { return nil }

        let maxShaftDev = shaftPts.map { perpDist($0, a: start, b: peak) }.max() ?? 0
        guard maxShaftDev / maxDist < (relaxed ? 0.10 : 0.07) else { return nil }

        // Tail after peak must fold back sharply toward the shaft
        let tailLen = hypot(end.x - peak.x, end.y - peak.y)
        guard tailLen >= 8, tailLen <= maxDist * 0.42 else { return nil }

        let shaftVec = CGPoint(x: peak.x - start.x, y: peak.y - start.y)
        let barbVec = CGPoint(x: end.x - peak.x, y: end.y - peak.y)
        let dot = (shaftVec.x * barbVec.x + shaftVec.y * barbVec.y) / (maxDist * tailLen)
        // `dot < -0.25` means the barb turns back by > 105°
        guard dot < -0.25 else { return nil }

        let snappedPeak = snapEndpointAngle(from: start, to: peak, toleranceDegrees: 5.5)
        let angle = atan2(snappedPeak.y - start.y, snappedPeak.x - start.x)
        let headLen = min(max(tailLen, 14), maxDist * 0.28)
        let wingAngle: CGFloat = .pi / 6 // 30°

        let leftWing = CGPoint(
            x: snappedPeak.x - headLen * cos(angle - wingAngle),
            y: snappedPeak.y - headLen * sin(angle - wingAngle)
        )
        let rightWing = CGPoint(
            x: snappedPeak.x - headLen * cos(angle + wingAngle),
            y: snappedPeak.y - headLen * sin(angle + wingAngle)
        )

        let arrowVertices = [start, snappedPeak, leftWing, snappedPeak, rightWing]
        return makePolygonStroke(arrowVertices, closed: false, like: stroke)
    }

    // MARK: - 3. Closed Polygon Recognition (Triangle, Rectangle/Square/Quad, Pentagon/Hexagon)

    private struct PolygonCandidate {
        let corners: [CGPoint]
        let shape: SnappedShape
        let normalizedError: CGFloat
    }

    private static func fitClosedPolygon(
        _ pts: [CGPoint],
        bounds: CGRect,
        diag: CGFloat,
        relaxed: Bool
    ) -> PolygonCandidate? {
        guard pts.count >= 6 else { return nil }

        // Re-order the closed loop starting from the vertex farthest from the centroid
        // (which is almost guaranteed to be a true corner rather than the middle of an edge!)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var startCornerIdx = 0
        var maxCornerDist: CGFloat = -1
        for (i, p) in pts.enumerated() {
            let d = hypot(p.x - center.x, p.y - center.y)
            if d > maxCornerDist {
                maxCornerDist = d
                startCornerIdx = i
            }
        }

        var ordered: [CGPoint] = Array(pts[startCornerIdx..<pts.count]) + Array(pts[0..<startCornerIdx])
        ordered.append(ordered[0]) // close loop explicitly

        // Try a few Ramer-Douglas-Peucker tolerances to extract clean corners
        var bestCandidate: PolygonCandidate?

        for factor in [0.055, 0.075, 0.095, 0.040] {
            let simplified = ramerDouglasPeucker(ordered, epsilon: diag * CGFloat(factor))
            // `simplified` includes the repeated closing vertex at the end
            guard simplified.count >= 4 else { continue }
            var corners = Array(simplified.dropLast())
            corners = mergeShallowCorners(corners, minTurnDegrees: 28, minEdgeLength: diag * 0.12)

            guard (3...6).contains(corners.count) else { continue }

            // Refine corners and regularize triangles/rectangles
            let regularized = regularizeCorners(corners, bounds: bounds, diag: diag)
            let err = meanDistanceToPolygonEdges(pts: pts, corners: regularized) / diag

            let maxAllowedErr: CGFloat = relaxed ? 0.068 : 0.048
            guard err <= maxAllowedErr else { continue }

            // Check that interior angles aren't degenerate (< 22°)
            guard hasValidInteriorAngles(regularized, minDegrees: 22) else { continue }

            let shape: SnappedShape
            switch regularized.count {
            case 3: shape = .triangle
            case 4: shape = .rect
            default: shape = .polygon
            }

            if bestCandidate == nil || err < bestCandidate!.normalizedError {
                bestCandidate = PolygonCandidate(corners: regularized, shape: shape, normalizedError: err)
            }
        }

        // Additional fallback specifically for axis-aligned Rectangles drawn with rounded corners
        let boxCorners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ]
        if bounds.width > diag * 0.22 && bounds.height > diag * 0.22 {
            let boxErr = meanDistanceToPolygonEdges(pts: pts, corners: boxCorners) / diag
            let maxBoxErr: CGFloat = relaxed ? 0.062 : 0.045
            if boxErr <= maxBoxErr && coversAllFourBoxSides(pts: pts, bounds: bounds) {
                let finalBox = regularizeAxisAlignedRect(bounds: bounds)
                if bestCandidate == nil || boxErr < bestCandidate!.normalizedError * 1.05 {
                    bestCandidate = PolygonCandidate(corners: finalBox, shape: .rect, normalizedError: boxErr)
                }
            }
        }

        return bestCandidate
    }

    /// Removes vertices where the path barely bends (< `minTurnDegrees`) or edges are tiny.
    private static func mergeShallowCorners(_ corners: [CGPoint], minTurnDegrees: CGFloat, minEdgeLength: CGFloat) -> [CGPoint] {
        var result = corners
        let minRad = minTurnDegrees * .pi / 180.0

        var changed = true
        while changed && result.count > 3 {
            changed = false
            for i in 0..<result.count {
                let prev = result[(i - 1 + result.count) % result.count]
                let curr = result[i]
                let next = result[(i + 1) % result.count]

                let d1 = hypot(curr.x - prev.x, curr.y - prev.y)
                let d2 = hypot(next.x - curr.x, next.y - curr.y)
                if d1 < minEdgeLength || d2 < minEdgeLength {
                    result.remove(at: i)
                    changed = true
                    break
                }

                let v1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
                let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
                let dot = v1.x * v2.x + v1.y * v2.y
                let cross = abs(v1.x * v2.y - v1.y * v2.x)
                let turnAngle = atan2(cross, dot)

                if turnAngle < minRad {
                    result.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    /// Regularizes 3-corner triangles (snapping nearly horizontal/vertical edges) and
    /// 4-corner quads (snapping nearly axis-aligned rectangles or squares).
    private static func regularizeCorners(_ corners: [CGPoint], bounds: CGRect, diag: CGFloat) -> [CGPoint] {
        if corners.count == 4 {
            // Check if all 4 edges are within 18° of horizontal or vertical
            var isNearlyAxisAligned = true
            for i in 0..<4 {
                let a = corners[i]
                let b = corners[(i + 1) % 4]
                let angle = abs(atan2(b.y - a.y, b.x - a.x))
                let distToHoriz = min(angle, abs(.pi - angle))
                let distToVert = abs(.pi / 2 - angle)
                if min(distToHoriz, distToVert) > (18.0 * .pi / 180.0) {
                    isNearlyAxisAligned = false
                    break
                }
            }
            if isNearlyAxisAligned {
                return regularizeAxisAlignedRect(bounds: bounds)
            }
        } else if corners.count == 3 {
            // If one edge of the triangle is within 8° of horizontal or vertical, level that edge
            var adjusted = corners
            for i in 0..<3 {
                let j = (i + 1) % 3
                let a = adjusted[i]
                let b = adjusted[j]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let angle = abs(atan2(dy, dx))
                if min(angle, abs(.pi - angle)) < (8.0 * .pi / 180.0) {
                    let midY = (a.y + b.y) / 2
                    adjusted[i].y = midY
                    adjusted[j].y = midY
                } else if abs(.pi / 2 - angle) < (8.0 * .pi / 180.0) {
                    let midX = (a.x + b.x) / 2
                    adjusted[i].x = midX
                    adjusted[j].x = midX
                }
            }
            return adjusted
        }
        return corners
    }

    private static func regularizeAxisAlignedRect(bounds: CGRect) -> [CGPoint] {
        var r = bounds
        // If aspect ratio is within 10% of 1:1, snap to a clean square
        let maxSide = max(r.width, r.height)
        if maxSide > 0 && abs(r.width - r.height) / maxSide < 0.10 {
            let side = (r.width + r.height) / 2
            r = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        }
        return [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY)
        ]
    }

    private static func coversAllFourBoxSides(pts: [CGPoint], bounds: CGRect) -> Bool {
        let tolX = bounds.width * 0.18
        let tolY = bounds.height * 0.18
        var top = 0, bottom = 0, left = 0, right = 0
        for p in pts {
            if abs(p.y - bounds.minY) <= tolY { top += 1 }
            if abs(p.y - bounds.maxY) <= tolY { bottom += 1 }
            if abs(p.x - bounds.minX) <= tolX { left += 1 }
            if abs(p.x - bounds.maxX) <= tolX { right += 1 }
        }
        let minPts = max(2, pts.count / 16)
        return top >= minPts && bottom >= minPts && left >= minPts && right >= minPts
    }

    private static func hasValidInteriorAngles(_ corners: [CGPoint], minDegrees: CGFloat) -> Bool {
        let minRad = minDegrees * .pi / 180.0
        let n = corners.count
        for i in 0..<n {
            let prev = corners[(i - 1 + n) % n]
            let curr = corners[i]
            let next = corners[(i + 1) % n]
            let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let dot = v1.x * v2.x + v1.y * v2.y
            let cross = abs(v1.x * v2.y - v1.y * v2.x)
            if atan2(cross, dot) < minRad {
                return false
            }
        }
        return true
    }

    // MARK: - 4. Circle & Ellipse Recognition

    private struct EllipseCandidate {
        let points: [CGPoint]
        let shape: SnappedShape
        let normalizedError: CGFloat
    }

    private static func fitCircleOrEllipse(
        _ pts: [CGPoint],
        bounds: CGRect,
        diag: CGFloat,
        relaxed: Bool
    ) -> EllipseCandidate? {
        guard pts.count >= 8 else { return nil }
        guard bounds.width > 14, bounds.height > 14 else { return nil }

        // Resample points uniformly along arc length so slow corners don't bias the fit
        let uniformPts = resampleUniformly(pts, count: 64, closed: true)
        let cx = uniformPts.map(\.x).reduce(0, +) / CGFloat(uniformPts.count)
        let cy = uniformPts.map(\.y).reduce(0, +) / CGFloat(uniformPts.count)

        // Principal component orientation
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in uniformPts {
            let dx = p.x - cx
            let dy = p.y - cy
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        var theta = 0.5 * atan2(2 * sxy, sxx - syy)
        // Snap orientation to 0 or 90 degrees if within 12°
        let deg = abs(theta) * 180.0 / .pi
        if deg < 12.0 || abs(deg - 90.0) < 12.0 || abs(deg - 180.0) < 12.0 {
            theta = 0
        }

        let cosT = cos(-theta)
        let sinT = sin(-theta)

        // Estimate semi-axes rx, ry in rotated frame using RMS projection (for an ellipse, E[u^2] = rx^2 / 2)
        var sumU2: CGFloat = 0
        var sumV2: CGFloat = 0
        for p in uniformPts {
            let dx = p.x - cx
            let dy = p.y - cy
            let u = dx * cosT - dy * sinT
            let v = dx * sinT + dy * cosT
            sumU2 += u * u
            sumV2 += v * v
        }
        var rx = sqrt(2.0 * sumU2 / CGFloat(uniformPts.count))
        var ry = sqrt(2.0 * sumV2 / CGFloat(uniformPts.count))
        guard rx > 8, ry > 8 else { return nil }

        // Snap nearly circular ellipses (aspect ratio >= 0.80) to a perfect circle
        let aspect = min(rx, ry) / max(rx, ry)
        let isCircle = aspect >= 0.80
        if isCircle {
            let r = (rx + ry) / 2.0
            rx = r
            ry = r
            theta = 0
        }

        // Measure how closely all stroke points lie on the fitted circle/ellipse
        let avgRadius = (rx + ry) / 2.0
        var totalRadialErr: CGFloat = 0
        var maxRadialErr: CGFloat = 0

        for p in uniformPts {
            let dx = p.x - cx
            let dy = p.y - cy
            let u = dx * cos(-theta) - dy * sin(-theta)
            let v = dx * sin(-theta) + dy * cos(-theta)
            let normR = hypot(u / rx, v / ry)
            let approxDist = abs(normR - 1.0) * avgRadius
            totalRadialErr += approxDist
            if approxDist > maxRadialErr {
                maxRadialErr = approxDist
            }
        }

        let meanNormErr = (totalRadialErr / CGFloat(uniformPts.count)) / diag
        let maxNormErr = maxRadialErr / avgRadius

        let allowedMean: CGFloat = relaxed ? 0.060 : 0.044
        let allowedMax: CGFloat = relaxed ? 0.30 : 0.22
        guard meanNormErr <= allowedMean, maxNormErr <= allowedMax else { return nil }

        let cosF = cos(theta)
        let sinF = sin(theta)
        let steps = 72
        // Add 2 extra steps past 2π so the closed stroke spline has a seamless join
        let curvePts: [CGPoint] = (0...(steps + 2)).map { i in
            let a = CGFloat(i) / CGFloat(steps) * 2.0 * .pi
            let u = rx * cos(a)
            let v = ry * sin(a)
            return CGPoint(
                x: cx + u * cosF - v * sinF,
                y: cy + u * sinF + v * cosF
            )
        }

        return EllipseCandidate(
            points: curvePts,
            shape: isCircle ? .circle : .ellipse,
            normalizedError: meanNormErr
        )
    }

    // MARK: - Ramer-Douglas-Peucker & Geometry Helpers

    private static func ramerDouglasPeucker(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var maxDist: CGFloat = 0
        var index = 0
        let first = pts.first!
        let last = pts.last!

        for i in 1..<(pts.count - 1) {
            let d = perpDistSegment(pts[i], a: first, b: last)
            if d > maxDist {
                maxDist = d
                index = i
            }
        }

        if maxDist > epsilon {
            let left = ramerDouglasPeucker(Array(pts[0...index]), epsilon: epsilon)
            let right = ramerDouglasPeucker(Array(pts[index..<pts.count]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private static func meanDistanceToPolygonEdges(pts: [CGPoint], corners: [CGPoint]) -> CGFloat {
        guard corners.count >= 2, !pts.isEmpty else { return .greatestFiniteMagnitude }
        let n = corners.count
        var sum: CGFloat = 0
        for p in pts {
            var minD = CGFloat.greatestFiniteMagnitude
            for i in 0..<n {
                let d = perpDistSegment(p, a: corners[i], b: corners[(i + 1) % n])
                if d < minD { minD = d }
            }
            sum += minD
        }
        return sum / CGFloat(pts.count)
    }

    private static func snapEndpointAngle(from a: CGPoint, to b: CGPoint, toleranceDegrees: CGFloat) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let tol = toleranceDegrees * .pi / 180.0

        // Snap to multiples of 45° (0°, ±45°, ±90°, ±135°, 180°)
        let step: CGFloat = .pi / 4
        let nearest = (angle / step).rounded() * step
        if abs(angle - nearest) <= tol {
            return CGPoint(x: a.x + len * cos(nearest), y: a.y + len * sin(nearest))
        }
        return b
    }

    private static func boundingBox(of pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in pts {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<pts.count {
            total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        }
        return total
    }

    private static func resampleUniformly(_ pts: [CGPoint], count: Int, closed: Bool) -> [CGPoint] {
        var working = pts
        if closed, let first = pts.first {
            working.append(first)
        }
        let totalLen = polylineLength(working)
        guard totalLen > 0, working.count >= 2, count >= 2 else { return pts }

        let step = totalLen / CGFloat(count)
        var result: [CGPoint] = [working[0]]
        var acc: CGFloat = 0
        var i = 1

        while i < working.count && result.count < count {
            let p0 = working[i - 1]
            let p1 = working[i]
            let segLen = hypot(p1.x - p0.x, p1.y - p0.y)
            if acc + segLen >= step && segLen > 0 {
                let remain = step - acc
                let t = remain / segLen
                let nx = p0.x + t * (p1.x - p0.x)
                let ny = p0.y + t * (p1.y - p0.y)
                let newPt = CGPoint(x: nx, y: ny)
                result.append(newPt)
                working[i - 1] = newPt
                acc = 0
            } else {
                acc += segLen
                i += 1
            }
        }
        return result
    }

    private static func perpDist(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    private static func perpDistSegment(_ p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    // MARK: - PencilKit Stroke Builders

    /// Builds a `PKStroke` with sharp corners by clamping B-spline vertices (repeating each corner)
    /// and subdividing straight segments so PencilKit never rounds off corners.
    private static func makePolygonStroke(_ vertices: [CGPoint], closed: Bool, like src: PKStroke) -> PKStroke {
        var poly = vertices
        if closed, let first = vertices.first {
            poly.append(first)
        }
        guard poly.count >= 2 else { return src }

        var densePoints: [CGPoint] = []
        for i in 0..<(poly.count - 1) {
            let a = poly[i]
            let b = poly[i + 1]
            let segLen = hypot(b.x - a.x, b.y - a.y)
            let subdivisions = max(2, Int(ceil(segLen / 10.0)))

            // Repeat corner point to clamp cubic B-spline so corners stay razor-sharp
            densePoints.append(a)
            densePoints.append(a)

            for s in 1..<subdivisions {
                let t = CGFloat(s) / CGFloat(subdivisions)
                densePoints.append(CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
            }

            densePoints.append(b)
            if i == poly.count - 2 {
                densePoints.append(b)
            }
        }

        return buildStroke(from: densePoints, like: src)
    }

    /// Builds a smooth curved `PKStroke` (for circles and ellipses).
    private static func makeCurveStroke(_ pts: [CGPoint], like src: PKStroke) -> PKStroke {
        return buildStroke(from: pts, like: src)
    }

    private static func buildStroke(from pts: [CGPoint], like src: PKStroke) -> PKStroke {
        let n = max(1, src.path.count)
        let avgForce   = (0..<n).map { src.path[$0].force      }.reduce(0, +) / CGFloat(n)
        let avgWidth   = (0..<n).map { src.path[$0].size.width }.reduce(0, +) / CGFloat(n)
        let avgAzimuth = (0..<n).map { src.path[$0].azimuth    }.reduce(0, +) / CGFloat(n)
        let avgAlt     = (0..<n).map { src.path[$0].altitude   }.reduce(0, +) / CGFloat(n)
        let sz = CGSize(width: avgWidth, height: avgWidth)

        let sPts: [PKStrokePoint] = pts.enumerated().map { i, pt in
            PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(i) * 0.005,
                size: sz,
                opacity: 1,
                force: avgForce,
                azimuth: avgAzimuth,
                altitude: avgAlt
            )
        }
        return PKStroke(
            ink: src.ink,
            path: PKStrokePath(controlPoints: sPts, creationDate: Date()),
            transform: .identity,
            mask: src.mask
        )
    }
}
