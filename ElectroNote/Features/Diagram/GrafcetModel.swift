import Foundation
import SwiftUI
import UIKit

// MARK: - GRAFCET Step Types (DIN EN 60848)

enum GrafcetStepType: String, CaseIterable, Identifiable, Codable {
    case normal     = "NORMAL"      // Einfacher Schritt (Quadrat)
    case initial    = "INITIAL"     // Initialschritt (Doppelrahmen)
    case macro      = "MACRO"       // Makroschritt (Doppelstrich oben und unten, z.B. M3)
    case enclosing  = "ENCLOSING"   // Einschließender Schritt (mit Rahmen)
    case entry      = "ENTRY"       // Eingangsschritt für Makro (E3 - Entrée)
    case exit       = "EXIT"        // Ausgangsschritt für Makro (S3 - Sortie)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:    return "Schritt"
        case .initial:   return "Initialschritt"
        case .macro:     return "Makroschritt"
        case .enclosing: return "Einschließender Schritt"
        case .entry:     return "Eingangsschritt (E)"
        case .exit:      return "Ausgangsschritt (S)"
        }
    }

    var icon: String {
        switch self {
        case .normal:    return "square"
        case .initial:   return "square.inset.filled"
        case .macro:     return "equal"
        case .enclosing: return "rectangle.dashed"
        case .entry:     return "arrow.right.to.line"
        case .exit:      return "arrow.right"
        }
    }
}

// MARK: - GRAFCET Action Types (DIN EN 60848 / S. Manemann Vorlage)

enum GrafcetActionType: String, CaseIterable, Identifiable, Codable {
    case continuous             = "CONTINUOUS"              // Kontinuierlich wirkend (früher N-Befehl)
    case assignationCondition    = "ASSIGNATION_CONDITION"   // Mit Zuweisungsbedingung (früher NC-Befehl)
    case storedActivation       = "STORED_ACTIVATION"       // Gespeichert bei Aktivierung (früher S-Befehl)
    case storedDeactivation     = "STORED_DEACTIVATION"     // Gespeichert bei Deaktivierung
    case storedEvent            = "STORED_EVENT"            // Gespeichert bei Ereignis
    case delayed                = "DELAYED"                 // Verzögert (früher D-Befehl) z.B. 1s/X2
    case timeLimited            = "TIME_LIMITED"            // Zeitbegrenzt (früher L-Befehl) z.B. 2s/X3
    case timeDependent          = "TIME_DEPENDENT"          // Zeitabhängig z.B. 1s/B4/2s

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuous:          return "Kontinuierlich (N)"
        case .assignationCondition: return "Mit Bedingung (NC)"
        case .storedActivation:    return "Bei Aktivierung (S ↑)"
        case .storedDeactivation:  return "Bei Deaktivierung (↓)"
        case .storedEvent:         return "Bei Ereignis (↑B)"
        case .delayed:             return "Verzögert (D)"
        case .timeLimited:         return "Zeitbegrenzt (L)"
        case .timeDependent:       return "Zeitabhängig (t1/B/t2)"
        }
    }

    var description: String {
        switch self {
        case .continuous:          return "Wird ausgeführt, solange der Schritt aktiv ist."
        case .assignationCondition: return "Wird nur ausgeführt, wenn die Zuweisungsbedingung erfüllt ist."
        case .storedActivation:    return "Weist bei Aktivierung des Schrittes einen Wert zu (z.B. M1:=1)."
        case .storedDeactivation:  return "Weist bei Deaktivierung des Schrittes einen Wert zu (z.B. M1:=0)."
        case .storedEvent:         return "Weist der Variablen bei Auftreten des Ereignisses einen Wert zu."
        case .delayed:             return "Aktivierung erfolgt zeitverzögert nach Schritt-Aktivierung (z.B. 1s/X2)."
        case .timeLimited:         return "Wird ab Schritt-Aktivierung für eine begrenzte Zeit aktiv (z.B. 2s/X3)."
        case .timeDependent:       return "Kombinierte Einschalt- und Ausschaltverzögerung (z.B. 1s/B4/2s)."
        }
    }

    var defaultQualifier: String {
        switch self {
        case .continuous:          return ""
        case .assignationCondition: return "B2"
        case .storedActivation:    return "↑"
        case .storedDeactivation:  return "↓"
        case .storedEvent:         return "↑B3"
        case .delayed:             return "1s/X2"
        case .timeLimited:         return "2s/X3"
        case .timeDependent:       return "1s/B4/2s"
        }
    }
}

// MARK: - GRAFCET Action Model

struct GrafcetAction: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var type: GrafcetActionType
    var variable: String                // e.g. "M1", "M1:=1", "Motor M2"
    var qualifierOrCondition: String    // e.g. "B2", "1s/X2", "↑B3"
    var comment: String                 // e.g. "Band läuft"

    init(
        id: UUID = UUID(),
        type: GrafcetActionType = .continuous,
        variable: String = "M1",
        qualifierOrCondition: String = "",
        comment: String = ""
    ) {
        self.id = id
        self.type = type
        self.variable = variable
        self.qualifierOrCondition = qualifierOrCondition.isEmpty ? type.defaultQualifier : qualifierOrCondition
        self.comment = comment
    }
}

// MARK: - GRAFCET Step Model

struct GrafcetStep: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var number: String                  // e.g. "1", "2", "3a", "M3", "E3", "S3"
    var type: GrafcetStepType
    var col: Int                        // Spalte im Raster
    var row: Int                        // Zeile im Raster
    var actions: [GrafcetAction] = []
    var isInitialOfEnclosure: Bool = false // mit * markiert
    var enclosingTitle: String = ""     // z.B. "Bearbeiten"

    init(
        id: UUID = UUID(),
        number: String = "1",
        type: GrafcetStepType = .normal,
        col: Int = 1,
        row: Int = 0,
        actions: [GrafcetAction] = [],
        isInitialOfEnclosure: Bool = false,
        enclosingTitle: String = ""
    ) {
        self.id = id
        self.number = number
        self.type = type
        self.col = col
        self.row = row
        self.actions = actions
        self.isInitialOfEnclosure = isInitialOfEnclosure
        self.enclosingTitle = enclosingTitle
    }
}

// MARK: - GRAFCET Transition Model

struct GrafcetTransition: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String                    // e.g. "1", "2", "(5)"
    var condition: String               // e.g. "B1", "B1*B2", "B4+B5", "1", "3s/X2", "↑S1", "!B2"
    var col: Int
    var row: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        condition: String = "1",
        col: Int = 1,
        row: Int = 1
    ) {
        self.id = id
        self.name = name
        self.condition = condition
        self.col = col
        self.row = row
    }
}

// MARK: - GRAFCET Connection Types & Model

enum GrafcetConnectionType: String, CaseIterable, Identifiable, Codable {
    case sequence   = "SEQUENCE"    // Vertikale Direktverbindung (Schritt -> Transition -> Schritt)
    case orBranch   = "OR_BRANCH"   // Ablaufverzweigung (ODER) - einfache Querlinie
    case orJoin     = "OR_JOIN"     // Ablaufzusammenführung (ODER) - einfache Querlinie
    case andSplit   = "AND_SPLIT"   // Ablaufspaltung (UND / Synchronisation) - doppelter Querbalken
    case andJoin    = "AND_JOIN"    // Ablaufsammlung (UND / Synchronisation) - doppelter Querbalken
    case loopBack   = "LOOP_BACK"   // Rückführung / Schleife (nach links geführt mit Pfeil nach oben)
    case jump       = "JUMP"        // Sprungmarke (Pfeil mit Ziel-Schrittnummer)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequence: return "Sequenz (Linie)"
        case .orBranch: return "ODER-Verzweigung"
        case .orJoin:   return "ODER-Zusammenführung"
        case .andSplit: return "UND-Ablaufspaltung (Doppelbalken)"
        case .andJoin:  return "UND-Ablaufsammlung (Doppelbalken)"
        case .loopBack: return "Rückführung (Schleife ↑)"
        case .jump:     return "Sprung (→ Schritt)"
        }
    }
}

struct GrafcetConnection: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var fromId: UUID
    var toId: UUID
    var type: GrafcetConnectionType = .sequence
    var customLabel: String = ""

    init(
        id: UUID = UUID(),
        fromId: UUID,
        toId: UUID,
        type: GrafcetConnectionType = .sequence,
        customLabel: String = ""
    ) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.type = type
        self.customLabel = customLabel
    }
}

// MARK: - Layout Grid Configuration

struct GrafcetGrid {
    static let stepSize: CGFloat = 56
    static let colWidth: CGFloat = 280
    static let rowHeight: CGFloat = 90
    static let originX: CGFloat = 280
    static let originY: CGFloat = 90

    static func center(col: Int, row: Int) -> CGPoint {
        let x = originX + CGFloat(col - 1) * colWidth
        let y = originY + CGFloat(row) * rowHeight
        return CGPoint(x: x, y: y)
    }

    static func nearestGrid(from point: CGPoint) -> (col: Int, row: Int) {
        let col = max(0, min(8, Int(round((point.x - originX) / colWidth)) + 1))
        let row = max(0, min(40, Int(round((point.y - originY) / rowHeight))))
        return (col, row)
    }
}

// MARK: - Document DTO & Templates

struct GrafcetDocumentDTO: Codable {
    var id: String
    var name: String
    var type: String // "grafcet"
    var createdAt: Int64
    var updatedAt: Int64
    var steps: [GrafcetStep]
    var transitions: [GrafcetTransition]
    var connections: [GrafcetConnection]
    var isDarkMode: Bool? = false

    init(
        id: String = UUID().uuidString,
        name: String,
        type: String = "grafcet",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        steps: [GrafcetStep] = [],
        transitions: [GrafcetTransition] = [],
        connections: [GrafcetConnection] = [],
        isDarkMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.steps = steps
        self.transitions = transitions
        self.connections = connections
        self.isDarkMode = isDarkMode
    }

    // Standard-Vorlage: Klassische lineare Schrittkette mit Initialschritt und Rückführung
    static func defaultTemplate(name: String) -> GrafcetDocumentDTO {
        let s1Id = UUID()
        let t1Id = UUID()
        let s2Id = UUID()
        let t2Id = UUID()

        let step1 = GrafcetStep(
            id: s1Id,
            number: "1",
            type: .initial,
            col: 1,
            row: 0,
            actions: [
                GrafcetAction(type: .continuous, variable: "P1", comment: "Bereit")
            ]
        )

        let trans1 = GrafcetTransition(
            id: t1Id,
            name: "1",
            condition: "B1",
            col: 1,
            row: 1
        )

        let step2 = GrafcetStep(
            id: s2Id,
            number: "2",
            type: .normal,
            col: 1,
            row: 2,
            actions: [
                GrafcetAction(type: .continuous, variable: "M1", comment: "Band läuft")
            ]
        )

        let trans2 = GrafcetTransition(
            id: t2Id,
            name: "2",
            condition: "B2",
            col: 1,
            row: 3
        )

        let conn1 = GrafcetConnection(fromId: s1Id, toId: t1Id, type: .sequence)
        let conn2 = GrafcetConnection(fromId: t1Id, toId: s2Id, type: .sequence)
        let conn3 = GrafcetConnection(fromId: s2Id, toId: t2Id, type: .sequence)
        let conn4 = GrafcetConnection(fromId: t2Id, toId: s1Id, type: .loopBack)

        return GrafcetDocumentDTO(
            name: name,
            steps: [step1, step2],
            transitions: [trans1, trans2],
            connections: [conn1, conn2, conn3, conn4]
        )
    }

    // Vorlage: Vollständige Referenz aller 8 Aktionstypen nach Manemann (002 Übersichtsbefehle_Grafcet)
    static func manemannReferenceTemplate(name: String) -> GrafcetDocumentDTO {
        let s1 = GrafcetStep(
            id: UUID(),
            number: "1",
            type: .initial,
            col: 1,
            row: 0,
            actions: [
                GrafcetAction(type: .continuous, variable: "Motor M1", comment: "Kontinuierlich")
            ]
        )

        let s2 = GrafcetStep(
            id: UUID(),
            number: "2",
            type: .normal,
            col: 1,
            row: 2,
            actions: [
                GrafcetAction(type: .assignationCondition, variable: "M1", qualifierOrCondition: "B2", comment: "Mit Zuweisungsbedingung")
            ]
        )

        let s3 = GrafcetStep(
            id: UUID(),
            number: "3",
            type: .normal,
            col: 1,
            row: 4,
            actions: [
                GrafcetAction(type: .storedActivation, variable: "M1:=1", qualifierOrCondition: "↑", comment: "Bei Aktivierung")
            ]
        )

        let s4 = GrafcetStep(
            id: UUID(),
            number: "4",
            type: .normal,
            col: 1,
            row: 6,
            actions: [
                GrafcetAction(type: .storedDeactivation, variable: "M1:=0", qualifierOrCondition: "↓", comment: "Bei Deaktivierung")
            ]
        )

        let s5 = GrafcetStep(
            id: UUID(),
            number: "5",
            type: .normal,
            col: 1,
            row: 8,
            actions: [
                GrafcetAction(type: .storedEvent, variable: "M1:=1", qualifierOrCondition: "↑B3", comment: "Bei Ereignis")
            ]
        )

        let s6 = GrafcetStep(
            id: UUID(),
            number: "6",
            type: .normal,
            col: 1,
            row: 10,
            actions: [
                GrafcetAction(type: .delayed, variable: "M1", qualifierOrCondition: "1s/X6", comment: "Verzögert")
            ]
        )

        let s7 = GrafcetStep(
            id: UUID(),
            number: "7",
            type: .normal,
            col: 1,
            row: 12,
            actions: [
                GrafcetAction(type: .timeLimited, variable: "M2", qualifierOrCondition: "2s/X7", comment: "Zeitbegrenzt")
            ]
        )

        let s8 = GrafcetStep(
            id: UUID(),
            number: "8",
            type: .normal,
            col: 1,
            row: 14,
            actions: [
                GrafcetAction(type: .timeDependent, variable: "M3", qualifierOrCondition: "1s/B4/2s", comment: "Zeitabhängig")
            ]
        )

        var transitions: [GrafcetTransition] = []
        var connections: [GrafcetConnection] = []
        let allSteps = [s1, s2, s3, s4, s5, s6, s7, s8]

        for i in 0..<allSteps.count - 1 {
            let t = GrafcetTransition(
                id: UUID(),
                name: "\(i + 1)",
                condition: "B\(i + 1)",
                col: 1,
                row: (i * 2) + 1
            )
            transitions.append(t)
            connections.append(GrafcetConnection(fromId: allSteps[i].id, toId: t.id, type: .sequence))
            connections.append(GrafcetConnection(fromId: t.id, toId: allSteps[i + 1].id, type: .sequence))
        }

        let lastT = GrafcetTransition(
            id: UUID(),
            name: "\(allSteps.count)",
            condition: "S3",
            col: 1,
            row: (allSteps.count - 1) * 2 + 1
        )
        transitions.append(lastT)
        connections.append(GrafcetConnection(fromId: allSteps.last!.id, toId: lastT.id, type: .sequence))
        connections.append(GrafcetConnection(fromId: lastT.id, toId: allSteps.first!.id, type: .loopBack))

        return GrafcetDocumentDTO(
            name: name,
            steps: allSteps,
            transitions: transitions,
            connections: connections
        )
    }
}

// MARK: - Document Store

final class GrafcetDocumentStore {
    let folderURL: URL

    var documentURL: URL {
        folderURL.appendingPathComponent("document.json")
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    func load() -> GrafcetDocumentDTO? {
        guard FileManager.default.fileExists(atPath: documentURL.path),
              let data = try? Data(contentsOf: documentURL) else {
            return nil
        }
        return try? JSONDecoder().decode(GrafcetDocumentDTO.self, from: data)
    }

    func save(_ doc: GrafcetDocumentDTO) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(doc) {
            try? data.write(to: documentURL, options: .atomic)
        }
    }
}
