import Foundation
import PencilKit
import UIKit

// MARK: - Portable Stroke DTO (matches Android IosNotebookBridge strokes.json / drawing.json)

struct PortableStrokeDTO: Codable {
    var color: Int64
    var width: Double
    var points: [[Double]] // [x, y, pressure]
}

final class PencilKitBridge {

    // MARK: - Export: PKDrawing -> Portable JSON

    static func portableStrokes(from drawing: PKDrawing) -> [PortableStrokeDTO] {
        var result: [PortableStrokeDTO] = []

        for stroke in drawing.strokes {
            guard stroke.path.count >= 2 else { continue }
            let color = stroke.ink.color.argbInt64
            let strokeWidth = Double(stroke.path[0].size.width)

            var points: [[Double]] = []
            points.reserveCapacity(stroke.path.count)

            for i in 0..<stroke.path.count {
                let pt = stroke.path[i]
                points.append([
                    Double(round(pt.location.x * 10) / 10),
                    Double(round(pt.location.y * 10) / 10),
                    Double(round(pt.force * 100) / 100)
                ])
            }

            result.append(PortableStrokeDTO(
                color: color,
                width: strokeWidth > 0 ? strokeWidth : 3.0,
                points: points
            ))
        }

        return result
    }

    // MARK: - Import: Portable JSON -> PKDrawing

    static func drawing(fromPortableStrokes strokes: [PortableStrokeDTO]) -> PKDrawing {
        var pkStrokes: [PKStroke] = []

        for strokeDTO in strokes {
            guard strokeDTO.points.count >= 2 else { continue }
            let uiColor = UIColor(argbInt: strokeDTO.color)
            let ink = PKInk(.pen, color: uiColor)
            let width = CGFloat(strokeDTO.width > 0 ? strokeDTO.width : 3.0)

            var strokePoints: [PKStrokePoint] = []
            strokePoints.reserveCapacity(strokeDTO.points.count)

            var time: TimeInterval = 0
            for p in strokeDTO.points {
                guard p.count >= 2 else { continue }
                let x = CGFloat(p[0])
                let y = CGFloat(p[1])
                let force = CGFloat(p.count > 2 ? p[2] : 1.0)
                let pt = PKStrokePoint(
                    location: CGPoint(x: x, y: y),
                    timeOffset: time,
                    size: CGSize(width: width, height: width),
                    opacity: 1.0,
                    force: force,
                    azimuth: 0,
                    altitude: .pi / 2
                )
                strokePoints.append(pt)
                time += 0.005
            }

            let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
            let pkStroke = PKStroke(ink: ink, path: path)
            pkStrokes.append(pkStroke)
        }

        return PKDrawing(strokes: pkStrokes)
    }

    // MARK: - File I/O Helpers

    static func loadDrawing(from jsonURL: URL) -> PKDrawing? {
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let dtos = try? JSONDecoder().decode([PortableStrokeDTO].self, from: data) else {
            return nil
        }
        return drawing(fromPortableStrokes: dtos)
    }

    static func saveDrawing(_ drawing: PKDrawing, to jsonURL: URL) {
        let dtos = portableStrokes(from: drawing)
        if let data = try? JSONEncoder().encode(dtos) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }
}
