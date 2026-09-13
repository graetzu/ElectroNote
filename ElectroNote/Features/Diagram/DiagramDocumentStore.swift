import Foundation
import UIKit
import SwiftUI

// MARK: - Cross-Platform Diagram DTOs (1:1 with Android DiagramDocument)

struct DiagramDocumentDTO: Codable {
    var id: String
    var name: String
    var type: String // "pap" or "mindmap"
    var createdAt: Int64
    var updatedAt: Int64
    var nodes: [DiagramNodeDTO]
    var connections: [DiagramConnectionDTO]
    var bypassDistancePx: Double?

    init(
        id: String = UUID().uuidString,
        name: String,
        type: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nodes: [DiagramNodeDTO] = [],
        connections: [DiagramConnectionDTO] = [],
        bypassDistancePx: Double? = 28.0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nodes = nodes
        self.connections = connections
        self.bypassDistancePx = bypassDistancePx
    }
}

struct DiagramNodeDTO: Codable {
    var id: String
    var x: Double
    var y: Double
    var shape: String // START, END, PROCESS, IO, DECISION, SUBROUTINE, COMMENT, CONNECTOR, CIRCLE, OVAL, RECTANGLE, DIAMOND
    var text: String
    var color: Int64?
    var col: Int?
    var row: Int?
    var tag: String?
}

struct DiagramConnectionDTO: Codable {
    var id: String
    var fromNodeId: String
    var toNodeId: String
    var label: String
    var fromPort: String // "BOTTOM", "TOP", "LEFT", "RIGHT"
}

// MARK: - Color Conversion Helpers for Cross-Platform ARGB Int64

extension UIColor {
    convenience init(argbInt: Int64) {
        let a = CGFloat((argbInt >> 24) & 0xFF) / 255.0
        let r = CGFloat((argbInt >> 16) & 0xFF) / 255.0
        let g = CGFloat((argbInt >> 8) & 0xFF) / 255.0
        let b = CGFloat(argbInt & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a > 0 ? a : 1.0)
    }

    var argbInt64: Int64 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ai = (Int64(round(a * 255.0)) & 0xFF)
        let ri = (Int64(round(r * 255.0)) & 0xFF)
        let gi = (Int64(round(g * 255.0)) & 0xFF)
        let bi = (Int64(round(b * 255.0)) & 0xFF)
        return (ai << 24) | (ri << 16) | (gi << 8) | bi
    }
}

// MARK: - Diagram Document Store

final class DiagramDocumentStore {
    let folderURL: URL

    var documentURL: URL {
        folderURL.appendingPathComponent("document.json")
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    func load() -> DiagramDocumentDTO? {
        guard FileManager.default.fileExists(atPath: documentURL.path),
              let data = try? Data(contentsOf: documentURL) else {
            return nil
        }
        return try? JSONDecoder().decode(DiagramDocumentDTO.self, from: data)
    }

    func save(_ doc: DiagramDocumentDTO) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(doc) {
            try? data.write(to: documentURL, options: .atomic)
        }
    }
}
