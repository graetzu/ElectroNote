import SwiftUI
import PencilKit
import UIKit

// MARK: - GRAFCET Theme & Dark Mode
struct GrafcetTheme {
    let isDark: Bool

    static let light = GrafcetTheme(isDark: false)
    static let dark = GrafcetTheme(isDark: true)

    var canvasBackground: Color {
        isDark ? Color(red: 0.11, green: 0.13, blue: 0.17) : Color.white
    }

    var canvasBackgroundUIColor: UIColor {
        isDark ? UIColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1.0) : UIColor.white
    }

    var gridDotColor: Color {
        isDark ? Color(white: 0.28) : Color(white: 0.85)
    }

    var strokeColor: Color {
        isDark ? Color(white: 0.95) : Color.black
    }

    var strokeUIColor: UIColor {
        isDark ? UIColor(white: 0.95, alpha: 1.0) : UIColor.black
    }

    var stepFillColor: Color {
        isDark ? Color(red: 0.16, green: 0.19, blue: 0.25) : Color.white
    }

    var stepFillUIColor: UIColor {
        isDark ? UIColor(red: 0.16, green: 0.19, blue: 0.25, alpha: 1.0) : UIColor.white
    }

    var textColor: Color {
        isDark ? Color.white : Color.black
    }

    var textUIColor: UIColor {
        isDark ? UIColor.white : UIColor.black
    }

    var secondaryTextColor: Color {
        isDark ? Color(white: 0.70) : Color.secondary
    }

    var secondaryTextUIColor: UIColor {
        isDark ? UIColor(white: 0.70, alpha: 1.0) : UIColor.secondaryLabel
    }

    var transitionBarColor: Color {
        isDark ? Color.white : Color.black
    }
}

// MARK: - GRAFCET View Model

@MainActor
final class GrafcetViewModel: ObservableObject {
    @Published var documentId: String = UUID().uuidString
    @Published var documentName: String = "GRAFCET"
    @Published var steps: [GrafcetStep] = []
    @Published var transitions: [GrafcetTransition] = []
    @Published var connections: [GrafcetConnection] = []

    // Selection
    @Published var selectedStepId: UUID? = nil
    @Published var selectedTransitionId: UUID? = nil
    @Published var selectedActionId: UUID? = nil

    // Canvas Transform
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGPoint = .zero

    // Grid Settings
    @Published var showGrid: Bool = true

    // Dark Mode / Theme
    @Published var isDarkMode: Bool = false

    var theme: GrafcetTheme {
        GrafcetTheme(isDark: isDarkMode)
    }

    // Undo / Redo
    private var undoStack: [([GrafcetStep], [GrafcetTransition], [GrafcetConnection])] = []
    private var redoStack: [([GrafcetStep], [GrafcetTransition], [GrafcetConnection])] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var store: GrafcetDocumentStore?

    init(item: DocumentItem) {
        self.store = GrafcetDocumentStore(folderURL: item.path)
        self.documentName = item.name
        load()
        setupLiveCollabHooks()
    }

    func load() {
        if let doc = store?.load() {
            applyDTO(doc)
        } else {
            let initial = GrafcetDocumentDTO.defaultTemplate(name: documentName)
            applyDTO(initial)
            store?.save(initial)
        }
    }

    func applyDTO(_ dto: GrafcetDocumentDTO) {
        self.documentId = dto.id
        self.documentName = dto.name
        self.steps = dto.steps
        self.transitions = dto.transitions
        self.connections = dto.connections
        self.isDarkMode = dto.isDarkMode ?? false
    }

    func exportDTO() -> GrafcetDocumentDTO {
        GrafcetDocumentDTO(
            id: documentId,
            name: documentName,
            steps: steps,
            transitions: transitions,
            connections: connections,
            isDarkMode: isDarkMode
        )
    }

    func save() {
        let dto = exportDTO()
        store?.save(dto)
        broadcastCurrentState()
    }

    private func pushUndo() {
        undoStack.append((steps, transitions, connections))
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        save()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append((steps, transitions, connections))
        steps = prev.0
        transitions = prev.1
        connections = prev.2
        save()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((steps, transitions, connections))
        steps = next.0
        transitions = next.1
        connections = next.2
        save()
    }

    // MARK: - Selection Helpers

    func selectStep(id: UUID) {
        selectedStepId = id
        selectedTransitionId = nil
        selectedActionId = nil
    }

    func selectTransition(id: UUID) {
        selectedTransitionId = id
        selectedStepId = nil
        selectedActionId = nil
    }

    func selectAction(id: UUID, stepId: UUID) {
        selectedActionId = id
        selectedStepId = stepId
        selectedTransitionId = nil
    }

    func clearSelection() {
        selectedStepId = nil
        selectedTransitionId = nil
        selectedActionId = nil
    }

    // MARK: - Step Operations

    func addStep(col: Int? = nil, row: Int? = nil, type: GrafcetStepType = .normal) -> GrafcetStep {
        pushUndo()
        let c = col ?? 1
        let r: Int
        if let specifiedRow = row {
            r = specifiedRow
        } else {
            let maxRow = max(
                steps.filter { $0.col == c }.map(\.row).max() ?? -1,
                transitions.filter { $0.col == c }.map(\.row).max() ?? -1
            )
            r = maxRow + 1
        }

        let nextNum = "\(steps.count + 1)"
        let step = GrafcetStep(number: nextNum, type: type, col: c, row: r)
        steps.append(step)
        selectStep(id: step.id)
        save()
        return step
    }

    func updateStep(_ step: GrafcetStep) {
        guard let idx = steps.firstIndex(where: { $0.id == step.id }) else { return }
        pushUndo()
        steps[idx] = step
        save()
    }

    func deleteStep(id: UUID) {
        pushUndo()
        steps.removeAll { $0.id == id }
        connections.removeAll { $0.fromId == id || $0.toId == id }
        clearSelection()
        save()
    }

    // MARK: - Transition Operations

    func addTransition(col: Int? = nil, row: Int? = nil, condition: String = "1", name: String = "") -> GrafcetTransition {
        pushUndo()
        let c = col ?? 1
        let r: Int
        if let specifiedRow = row {
            r = specifiedRow
        } else {
            let maxRow = max(
                steps.filter { $0.col == c }.map(\.row).max() ?? -1,
                transitions.filter { $0.col == c }.map(\.row).max() ?? -1
            )
            r = maxRow + 1
        }

        let transName = name.isEmpty ? "\(transitions.count + 1)" : name
        let trans = GrafcetTransition(name: transName, condition: condition, col: c, row: r)
        transitions.append(trans)
        selectTransition(id: trans.id)
        save()
        return trans
    }

    func updateTransition(_ trans: GrafcetTransition) {
        guard let idx = transitions.firstIndex(where: { $0.id == trans.id }) else { return }
        pushUndo()
        transitions[idx] = trans
        save()
    }

    func deleteTransition(id: UUID) {
        pushUndo()
        transitions.removeAll { $0.id == id }
        connections.removeAll { $0.fromId == id || $0.toId == id }
        clearSelection()
        save()
    }

    // MARK: - Action Operations

    func addAction(to stepId: UUID, type: GrafcetActionType = .continuous, variable: String = "M1", qualifier: String = "", comment: String = "") {
        guard let sIdx = steps.firstIndex(where: { $0.id == stepId }) else { return }
        pushUndo()
        let action = GrafcetAction(
            type: type,
            variable: variable,
            qualifierOrCondition: qualifier.isEmpty ? type.defaultQualifier : qualifier,
            comment: comment
        )
        steps[sIdx].actions.append(action)
        selectAction(id: action.id, stepId: stepId)
        save()
    }

    func updateAction(stepId: UUID, action: GrafcetAction) {
        guard let sIdx = steps.firstIndex(where: { $0.id == stepId }),
              let aIdx = steps[sIdx].actions.firstIndex(where: { $0.id == action.id }) else { return }
        pushUndo()
        steps[sIdx].actions[aIdx] = action
        save()
    }

    func deleteAction(stepId: UUID, actionId: UUID) {
        guard let sIdx = steps.firstIndex(where: { $0.id == stepId }) else { return }
        pushUndo()
        steps[sIdx].actions.removeAll { $0.id == actionId }
        clearSelection()
        save()
    }

    // MARK: - Connection Operations

    func connect(from: UUID, to: UUID, type: GrafcetConnectionType = .sequence) {
        if connections.contains(where: { $0.fromId == from && $0.toId == to }) { return }
        pushUndo()
        let conn = GrafcetConnection(fromId: from, toId: to, type: type)
        connections.append(conn)
        save()
    }

    func deleteConnection(id: UUID) {
        pushUndo()
        connections.removeAll { $0.id == id }
        save()
    }

    // MARK: - Smart Chaining & Structures

    func appendTransitionBelow(step: GrafcetStep) {
        pushUndo()
        let targetRow = step.row + 1
        let trans = GrafcetTransition(
            name: "\(transitions.count + 1)",
            condition: "B\(transitions.count + 1)",
            col: step.col,
            row: targetRow
        )
        transitions.append(trans)
        connections.append(GrafcetConnection(fromId: step.id, toId: trans.id, type: .sequence))
        selectTransition(id: trans.id)
        save()
    }

    func appendStepBelow(transition: GrafcetTransition) {
        pushUndo()
        let targetRow = transition.row + 1
        let nextNum = "\(steps.count + 1)"
        let step = GrafcetStep(
            number: nextNum,
            type: .normal,
            col: transition.col,
            row: targetRow,
            actions: [GrafcetAction(type: .continuous, variable: "M\(nextNum)")]
        )
        steps.append(step)
        connections.append(GrafcetConnection(fromId: transition.id, toId: step.id, type: .sequence))
        selectStep(id: step.id)
        save()
    }

    func createLoopBack(from trans: GrafcetTransition, to step: GrafcetStep) {
        pushUndo()
        connections.append(GrafcetConnection(fromId: trans.id, toId: step.id, type: .loopBack))
        save()
    }

    // Vorlagen laden
    func loadTemplate(_ template: TemplateKind) {
        pushUndo()
        let dto: GrafcetDocumentDTO
        switch template {
        case .linear:
            dto = GrafcetDocumentDTO.defaultTemplate(name: documentName)
        case .manemann:
            dto = GrafcetDocumentDTO.manemannReferenceTemplate(name: documentName)
        case .orBranch:
            dto = createOrBranchTemplate()
        case .andSync:
            dto = createAndSyncTemplate()
        }
        applyDTO(dto)
        save()
    }

    enum TemplateKind: String, CaseIterable, Identifiable {
        case linear = "Lineare Kette (Standard)"
        case orBranch = "ODER-Verzweigung (Ablaufauswahl)"
        case andSync = "UND-Synchronisation (Doppelbalken)"
        case manemann = "Manemann-Übersicht (Alle 8 Aktionstypen)"

        var id: String { rawValue }
    }

    private func createOrBranchTemplate() -> GrafcetDocumentDTO {
        let s2Id = UUID(), t1Id = UUID(), t2Id = UUID()
        let s3aId = UUID(), s3bId = UUID()
        let t3Id = UUID(), t4Id = UUID(), s4Id = UUID()

        let s2 = GrafcetStep(id: s2Id, number: "2", type: .initial, col: 1, row: 0, actions: [GrafcetAction(variable: "P1")])
        let t1 = GrafcetTransition(id: t1Id, name: "", condition: "B1", col: 1, row: 1)
        let t2 = GrafcetTransition(id: t2Id, name: "", condition: "!B1", col: 2, row: 1)

        let s3a = GrafcetStep(id: s3aId, number: "3a", type: .normal, col: 1, row: 2, actions: [GrafcetAction(variable: "M1")])
        let s3b = GrafcetStep(id: s3bId, number: "3b", type: .normal, col: 2, row: 2, actions: [GrafcetAction(variable: "M2")])

        let t3 = GrafcetTransition(id: t3Id, name: "", condition: "B4", col: 1, row: 3)
        let t4 = GrafcetTransition(id: t4Id, name: "", condition: "B5", col: 2, row: 3)

        let s4 = GrafcetStep(id: s4Id, number: "4", type: .normal, col: 1, row: 4, actions: [GrafcetAction(variable: "P5")])

        let conns = [
            GrafcetConnection(fromId: s2Id, toId: t1Id, type: .orBranch),
            GrafcetConnection(fromId: s2Id, toId: t2Id, type: .orBranch),
            GrafcetConnection(fromId: t1Id, toId: s3aId, type: .sequence),
            GrafcetConnection(fromId: t2Id, toId: s3bId, type: .sequence),
            GrafcetConnection(fromId: s3aId, toId: t3Id, type: .sequence),
            GrafcetConnection(fromId: s3bId, toId: t4Id, type: .sequence),
            GrafcetConnection(fromId: t3Id, toId: s4Id, type: .orJoin),
            GrafcetConnection(fromId: t4Id, toId: s4Id, type: .orJoin),
            GrafcetConnection(fromId: s4Id, toId: s2Id, type: .loopBack)
        ]

        return GrafcetDocumentDTO(
            name: documentName,
            steps: [s2, s3a, s3b, s4],
            transitions: [t1, t2, t3, t4],
            connections: conns
        )
    }

    private func createAndSyncTemplate() -> GrafcetDocumentDTO {
        let s2Id = UUID(), t1Id = UUID()
        let s3aId = UUID(), s3bId = UUID()
        let t2Id = UUID(), t3Id = UUID()
        let s4aId = UUID(), s4bId = UUID()
        let t4Id = UUID(), s5Id = UUID()

        let s2 = GrafcetStep(id: s2Id, number: "2", type: .initial, col: 1, row: 0, actions: [GrafcetAction(variable: "P1")])
        let t1 = GrafcetTransition(id: t1Id, name: "1", condition: "B1", col: 1, row: 1)

        let s3a = GrafcetStep(id: s3aId, number: "3a", type: .normal, col: 1, row: 2, actions: [GrafcetAction(variable: "M1")])
        let s3b = GrafcetStep(id: s3bId, number: "3b", type: .normal, col: 2, row: 2, actions: [GrafcetAction(variable: "M2")])

        let t2 = GrafcetTransition(id: t2Id, name: "2", condition: "B2", col: 1, row: 3)
        let t3 = GrafcetTransition(id: t3Id, name: "3", condition: "B3", col: 2, row: 3)

        let s4a = GrafcetStep(id: s4aId, number: "4a", type: .normal, col: 1, row: 4, actions: [GrafcetAction(variable: "M6")])
        let s4b = GrafcetStep(id: s4bId, number: "4b", type: .normal, col: 2, row: 4, actions: [GrafcetAction(variable: "M8")])

        let t4 = GrafcetTransition(id: t4Id, name: "4", condition: "1", col: 1, row: 5)
        let s5 = GrafcetStep(id: s5Id, number: "5", type: .normal, col: 1, row: 6, actions: [GrafcetAction(variable: "P5")])

        let conns = [
            GrafcetConnection(fromId: s2Id, toId: t1Id, type: .sequence),
            GrafcetConnection(fromId: t1Id, toId: s3aId, type: .andSplit),
            GrafcetConnection(fromId: t1Id, toId: s3bId, type: .andSplit),
            GrafcetConnection(fromId: s3aId, toId: t2Id, type: .sequence),
            GrafcetConnection(fromId: s3bId, toId: t3Id, type: .sequence),
            GrafcetConnection(fromId: t2Id, toId: s4aId, type: .sequence),
            GrafcetConnection(fromId: t3Id, toId: s4bId, type: .sequence),
            GrafcetConnection(fromId: s4aId, toId: t4Id, type: .andJoin),
            GrafcetConnection(fromId: s4bId, toId: t4Id, type: .andJoin),
            GrafcetConnection(fromId: t4Id, toId: s5Id, type: .sequence),
            GrafcetConnection(fromId: s5Id, toId: s2Id, type: .loopBack)
        ]

        return GrafcetDocumentDTO(
            name: documentName,
            steps: [s2, s3a, s3b, s4a, s4b, s5],
            transitions: [t1, t2, t3, t4],
            connections: conns
        )
    }

    // MARK: - Live Collaboration

    func broadcastCurrentState() {
        let dto = exportDTO()
        if let data = try? JSONEncoder().encode(dto),
           let json = String(data: data, encoding: .utf8) {
            LiveCollabSessionManager.shared.sendDiagramAction(action: .nodeUpdated, nodeJson: json)
        }
    }

    func setupLiveCollabHooks() {
        let collab = LiveCollabSessionManager.shared

        collab.onProvideSnapshot = { [weak self] in
            guard let self = self else { return (nil, nil, nil, nil, nil) }
            let dto = self.exportDTO()
            let data = try? JSONEncoder().encode(dto)
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            return (json, nil, nil, self.documentName, nil)
        }

        collab.onApplySnapshot = { [weak self] docJson, _, _, _ in
            guard let self = self,
                  let docJson = docJson,
                  let data = docJson.data(using: .utf8),
                  let dto = try? JSONDecoder().decode(GrafcetDocumentDTO.self, from: data) else { return }
            self.applyDTO(dto)
            self.store?.save(dto)
        }

        collab.onRemoteDiagramAction = { [weak self] message in
            guard let self = self else { return }
            if let json = message.nodeJson,
               let data = json.data(using: .utf8),
               let dto = try? JSONDecoder().decode(GrafcetDocumentDTO.self, from: data) {
                self.applyDTO(dto)
                self.store?.save(dto)
            }
        }
    }

    // MARK: - CoreGraphics High-Resolution Rendering & Export

    func renderToImage(scale: CGFloat = 2.0) -> UIImage {
        let minCol = (steps.map(\.col) + transitions.map(\.col)).min() ?? 1
        let maxCol = (steps.map(\.col) + transitions.map(\.col)).max() ?? 2
        let minRow = (steps.map(\.row) + transitions.map(\.row)).min() ?? 0
        let maxRow = (steps.map(\.row) + transitions.map(\.row)).max() ?? 4

        let pMin = GrafcetGrid.center(col: minCol, row: minRow)
        let pMax = GrafcetGrid.center(col: maxCol, row: maxRow)

        let margin: CGFloat = 80
        let rect = CGRect(
            x: max(0, pMin.x - margin - 80),
            y: max(0, pMin.y - margin),
            width: (pMax.x - pMin.x) + 380 + margin * 2,
            height: (pMax.y - pMin.y) + 120 + margin * 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)

        return renderer.image { ctx in
            theme.canvasBackgroundUIColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))

            let cg = ctx.cgContext
            cg.translateBy(x: -rect.origin.x, y: -rect.origin.y)

            // 1. Connections
            for conn in connections {
                drawConnection(conn, in: cg)
            }

            // 2. Transitions
            for trans in transitions {
                drawTransition(trans, in: cg)
            }

            // 3. Steps & Actions
            for step in steps {
                drawStep(step, in: cg)
            }
        }
    }

    private func drawConnection(_ conn: GrafcetConnection, in cg: CGContext) {
        let p1: CGPoint
        let p2: CGPoint

        if let fromStep = steps.first(where: { $0.id == conn.fromId }) {
            p1 = CGPoint(x: GrafcetGrid.center(col: fromStep.col, row: fromStep.row).x,
                         y: GrafcetGrid.center(col: fromStep.col, row: fromStep.row).y + GrafcetGrid.stepSize / 2)
        } else if let fromTrans = transitions.first(where: { $0.id == conn.fromId }) {
            p1 = GrafcetGrid.center(col: fromTrans.col, row: fromTrans.row)
        } else { return }

        if let toStep = steps.first(where: { $0.id == conn.toId }) {
            p2 = CGPoint(x: GrafcetGrid.center(col: toStep.col, row: toStep.row).x,
                         y: GrafcetGrid.center(col: toStep.col, row: toStep.row).y - GrafcetGrid.stepSize / 2)
        } else if let toTrans = transitions.first(where: { $0.id == conn.toId }) {
            p2 = GrafcetGrid.center(col: toTrans.col, row: toTrans.row)
        } else { return }

        cg.saveGState()
        cg.setStrokeColor(theme.strokeUIColor.cgColor)
        cg.setLineWidth(2.0)

        switch conn.type {
        case .sequence:
            cg.move(to: p1)
            cg.addLine(to: p2)
            cg.strokePath()

        case .orBranch, .orJoin:
            cg.move(to: p1)
            let midY = (p1.y + p2.y) / 2
            cg.addLine(to: CGPoint(x: p1.x, y: midY))
            cg.addLine(to: CGPoint(x: p2.x, y: midY))
            cg.addLine(to: p2)
            cg.strokePath()

        case .andSplit, .andJoin:
            // Doppelter horizontaler Balken
            let midY = (p1.y + p2.y) / 2
            let leftX = min(p1.x, p2.x) - 30
            let rightX = max(p1.x, p2.x) + 30

            cg.setLineWidth(3.0)
            cg.move(to: CGPoint(x: leftX, y: midY - 2.5))
            cg.addLine(to: CGPoint(x: rightX, y: midY - 2.5))
            cg.strokePath()

            cg.move(to: CGPoint(x: leftX, y: midY + 2.5))
            cg.addLine(to: CGPoint(x: rightX, y: midY + 2.5))
            cg.strokePath()

            cg.setLineWidth(2.0)
            cg.move(to: p1)
            cg.addLine(to: CGPoint(x: p1.x, y: midY - 2.5))
            cg.move(to: CGPoint(x: p2.x, y: midY + 2.5))
            cg.addLine(to: p2)
            cg.strokePath()

        case .loopBack:
            // Links herausgeführter Rücksprung mit Pfeil nach oben
            let loopX = min(p1.x, p2.x) - 70
            cg.move(to: p1)
            cg.addLine(to: CGPoint(x: loopX, y: p1.y))
            cg.addLine(to: CGPoint(x: loopX, y: p2.y))
            cg.addLine(to: p2)
            cg.strokePath()

            // Pfeil nach oben auf der Rückführungsstrecke
            let arrowY = (p1.y + p2.y) / 2
            cg.setFillColor(theme.strokeUIColor.cgColor)
            let arrowPath = CGMutablePath()
            arrowPath.move(to: CGPoint(x: loopX, y: arrowY - 7))
            arrowPath.addLine(to: CGPoint(x: loopX - 5, y: arrowY + 5))
            arrowPath.addLine(to: CGPoint(x: loopX + 5, y: arrowY + 5))
            arrowPath.closeSubpath()
            cg.addPath(arrowPath)
            cg.fillPath()

        case .jump:
            cg.move(to: p1)
            cg.addLine(to: CGPoint(x: p1.x + 30, y: p1.y))
            cg.strokePath()
        }

        cg.restoreGState()
    }

    private func drawTransition(_ trans: GrafcetTransition, in cg: CGContext) {
        let center = GrafcetGrid.center(col: trans.col, row: trans.row)
        cg.saveGState()

        // Waagerechter Querbalken
        cg.setFillColor(theme.strokeUIColor.cgColor)
        cg.fill(CGRect(x: center.x - 20, y: center.y - 1.5, width: 40, height: 3))

        // Transitionsname links: (1)
        if !trans.name.isEmpty {
            let nameStr = "(\(trans.name))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: theme.secondaryTextUIColor
            ]
            let size = nameStr.size(withAttributes: attrs)
            nameStr.draw(at: CGPoint(x: center.x - 26 - size.width, y: center.y - size.height / 2), withAttributes: attrs)
        }

        // Transitionsbedingung rechts: z.B. B1*B2 oder 3s/X2
        let condStr = trans.condition as NSString
        let condAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: theme.textUIColor
        ]
        let condSize = condStr.size(withAttributes: condAttrs)
        condStr.draw(at: CGPoint(x: center.x + 26, y: center.y - condSize.height / 2), withAttributes: condAttrs)

        cg.restoreGState()
    }

    private func drawStep(_ step: GrafcetStep, in cg: CGContext) {
        let center = GrafcetGrid.center(col: step.col, row: step.row)
        let s = GrafcetGrid.stepSize
        let boxRect = CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s)

        cg.saveGState()
        cg.setFillColor(theme.stepFillUIColor.cgColor)
        cg.setStrokeColor(theme.strokeUIColor.cgColor)
        cg.setLineWidth(2.0)

        // Schritt-Box
        cg.fill(boxRect)
        cg.stroke(boxRect)

        // Doppelrahmen bei Initialschritt
        if step.type == .initial {
            let insetRect = boxRect.insetBy(dx: 4.5, dy: 4.5)
            cg.stroke(insetRect)
        }

        // Makroschritt: zwei horizontale Balken oben und unten
        if step.type == .macro {
            cg.setLineWidth(3.0)
            cg.move(to: CGPoint(x: boxRect.minX - 6, y: boxRect.minY))
            cg.addLine(to: CGPoint(x: boxRect.maxX + 6, y: boxRect.minY))
            cg.move(to: CGPoint(x: boxRect.minX - 6, y: boxRect.maxY))
            cg.addLine(to: CGPoint(x: boxRect.maxX + 6, y: boxRect.maxY))
            cg.strokePath()
            cg.setLineWidth(2.0)
        }

        // Schrittnummer in der Mitte
        let numStr = (step.isInitialOfEnclosure ? "* " : "") + step.number as NSString
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: theme.textUIColor
        ]
        let numSize = numStr.size(withAttributes: numAttrs)
        numStr.draw(at: CGPoint(x: center.x - numSize.width / 2, y: center.y - numSize.height / 2), withAttributes: numAttrs)

        // Aktionen rechts am Schritt
        var actionX = boxRect.maxX
        for action in step.actions {
            // Verbindungssteg
            cg.move(to: CGPoint(x: actionX, y: center.y))
            cg.addLine(to: CGPoint(x: actionX + 16, y: center.y))
            cg.strokePath()
            actionX += 16

            let actionW: CGFloat = max(100, (action.variable as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]).width + 32)
            let actionH: CGFloat = 44
            let aRect = CGRect(x: actionX, y: center.y - actionH / 2, width: actionW, height: actionH)

            // Hauptkasten
            cg.fill(aRect)
            cg.stroke(aRect)

            // Zuweisung / Variable Text
            let varStr = action.variable as NSString
            let varAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: theme.textUIColor
            ]
            let varSize = varStr.size(withAttributes: varAttrs)
            varStr.draw(at: CGPoint(x: aRect.midX - varSize.width / 2, y: aRect.midY - varSize.height / 2), withAttributes: varAttrs)

            // Aufsatz-Kästchen für Bedingung/Qualifizierer
            if !action.qualifierOrCondition.isEmpty {
                let qH: CGFloat = 18
                let qRect = CGRect(x: aRect.minX, y: aRect.minY - qH, width: aRect.width, height: qH)
                cg.fill(qRect)
                cg.stroke(qRect)

                let qStr = action.qualifierOrCondition as NSString
                let qAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: theme.textUIColor
                ]
                let qSize = qStr.size(withAttributes: qAttrs)
                qStr.draw(at: CGPoint(x: qRect.midX - qSize.width / 2, y: qRect.midY - qSize.height / 2), withAttributes: qAttrs)
            }

            // Kommentar in Anführungszeichen rechts
            if !action.comment.isEmpty {
                let comStr = "„\(action.comment)“" as NSString
                let comAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 13),
                    .foregroundColor: theme.secondaryTextUIColor
                ]
                comStr.draw(at: CGPoint(x: aRect.maxX + 10, y: aRect.midY - 7), withAttributes: comAttrs)
            }

            actionX += actionW + 16
        }

        cg.restoreGState()
    }
}

// MARK: - GRAFCET Designer View

struct GrafcetDesignerView: View {
    let item: DocumentItem
    let onExportImage: ((UIImage) -> Void)?

    @StateObject private var vm: GrafcetViewModel
    @Environment(\.dismiss) private var dismiss

    // Sheets & Popovers
    @State private var showStepInspector: Bool = false
    @State private var editingStep: GrafcetStep? = nil

    @State private var showTransitionInspector: Bool = false
    @State private var editingTransition: GrafcetTransition? = nil

    @State private var showActionInspector: Bool = false
    @State private var editingAction: GrafcetAction? = nil
    @State private var editingActionStepId: UUID? = nil

    @State private var showExportSuccess: Bool = false
    @State private var exportToastText: String = ""

    init(item: DocumentItem, onExportImage: ((UIImage) -> Void)? = nil) {
        self.item = item
        self.onExportImage = onExportImage
        _vm = StateObject(wrappedValue: GrafcetViewModel(item: item))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                vm.theme.canvasBackground
                    .ignoresSafeArea()

                // Interactive Infinite Canvas
                canvasView
                    .clipped()

                // Floating Action Toolbar (Bottom)
                VStack {
                    Spacer()
                    bottomToolbar
                        .padding(.bottom, 16)
                }

                // Toast Banner
                if showExportSuccess {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(exportToastText)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(vm.documentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        vm.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!vm.canUndo)

                    Button {
                        vm.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!vm.canRedo)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Direct 1-Tap Dark/Light Mode Switch
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.isDarkMode.toggle()
                            vm.save()
                        }
                    } label: {
                        Image(systemName: vm.isDarkMode ? "sun.max.fill" : "moon.fill")
                    }
                    .tint(vm.isDarkMode ? .yellow : .primary)
                    .help(vm.isDarkMode ? "Hellmodus aktivieren" : "Dunkelmodus aktivieren")

                    Menu {
                        Toggle("Dunkelmodus (Dark Mode)", isOn: Binding(
                            get: { vm.isDarkMode },
                            set: { val in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.isDarkMode = val
                                    vm.save()
                                }
                            }
                        ))

                        Toggle("Raster anzeigen", isOn: $vm.showGrid)

                        Divider()

                        Menu("Vorlagen") {
                            ForEach(GrafcetViewModel.TemplateKind.allCases) { template in
                                Button(template.rawValue) {
                                    vm.loadTemplate(template)
                                }
                            }
                        }

                        Divider()

                        Button {
                            exportImage()
                        } label: {
                            Label("Bild in Fotos sichern", systemImage: "photo")
                        }

                        Button {
                            shareImage()
                        } label: {
                            Label("GRAFCET teilen…", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showStepInspector) {
                if let step = editingStep {
                    GrafcetStepInspectorSheet(step: step) { updated in
                        vm.updateStep(updated)
                    } onDelete: {
                        vm.deleteStep(id: step.id)
                    } onAddAction: {
                        vm.addAction(to: step.id)
                    } onAppendTransition: {
                        vm.appendTransitionBelow(step: step)
                    }
                }
            }
            .sheet(isPresented: $showTransitionInspector) {
                if let trans = editingTransition {
                    GrafcetTransitionInspectorSheet(transition: trans) { updated in
                        vm.updateTransition(updated)
                    } onDelete: {
                        vm.deleteTransition(id: trans.id)
                    } onAppendStep: {
                        vm.appendStepBelow(transition: trans)
                    }
                }
            }
            .sheet(isPresented: $showActionInspector) {
                if let action = editingAction, let sId = editingActionStepId {
                    GrafcetActionInspectorSheet(action: action) { updated in
                        vm.updateAction(stepId: sId, action: updated)
                    } onDelete: {
                        vm.deleteAction(stepId: sId, actionId: action.id)
                    }
                }
            }
            .preferredColorScheme(vm.isDarkMode ? .dark : .light)
        }
    }

    // MARK: - Canvas View

    private var canvasView: some View {
        GeometryReader { proxy in
            ZStack {
                // Background Grid
                if vm.showGrid {
                    GrafcetGridBackgroundView(theme: vm.theme)
                } else {
                    vm.theme.canvasBackground
                }

                // Diagram Content Layer
                ZStack(alignment: .topLeading) {
                    // 1. Connection Lines Layer
                    ForEach(vm.connections) { conn in
                        connectionLine(conn)
                    }

                    // 2. Transitions Layer
                    ForEach(vm.transitions) { trans in
                        transitionNodeView(trans)
                    }

                    // 3. Steps Layer
                    ForEach(vm.steps) { step in
                        stepNodeView(step)
                    }
                }
                .scaleEffect(vm.zoomScale)
                .offset(x: vm.panOffset.x, y: vm.panOffset.y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        vm.panOffset.x += v.translation.width
                        vm.panOffset.y += v.translation.height
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        vm.zoomScale = max(0.4, min(3.0, vm.zoomScale * scale))
                    }
            )
            .onTapGesture {
                vm.clearSelection()
            }
        }
    }

    // MARK: - Step Node View

    private func stepNodeView(_ step: GrafcetStep) -> some View {
        let center = GrafcetGrid.center(col: step.col, row: step.row)
        let s = GrafcetGrid.stepSize
        let isSelected = vm.selectedStepId == step.id

        return HStack(spacing: 0) {
            // Main Step Box
            ZStack {
                // Outer Box
                Rectangle()
                    .fill(vm.theme.stepFillColor)
                    .frame(width: s, height: s)
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.accentColor : vm.theme.strokeColor, lineWidth: isSelected ? 3 : 2)
                    )

                // Double Border for Initial Step
                if step.type == .initial {
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : vm.theme.strokeColor, lineWidth: 1.8)
                        .padding(4.5)
                }

                // Macro Step Horizontal Bars
                if step.type == .macro {
                    VStack {
                        Rectangle().fill(vm.theme.strokeColor).frame(height: 3)
                        Spacer()
                        Rectangle().fill(vm.theme.strokeColor).frame(height: 3)
                    }
                    .frame(width: s + 12, height: s)
                }

                // Step Number
                Text((step.isInitialOfEnclosure ? "* " : "") + step.number)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(vm.theme.textColor)
            }
            .frame(width: s, height: s)
            .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 8)
            .onTapGesture {
                vm.selectStep(id: step.id)
                editingStep = step
                showStepInspector = true
            }

            // Attached Actions (Chained to the right)
            ForEach(step.actions) { action in
                actionBoxView(action: action, stepId: step.id)
            }
        }
        .position(x: center.x + (CGFloat(step.actions.count) * 60), y: center.y)
    }

    // MARK: - Action Box View

    private func actionBoxView(action: GrafcetAction, stepId: UUID) -> some View {
        let isSelected = vm.selectedActionId == action.id

        return HStack(spacing: 0) {
            // Connecting Bar from step / previous action
            Rectangle()
                .fill(vm.theme.strokeColor)
                .frame(width: 16, height: 2)

            // Action Card
            VStack(spacing: 0) {
                // Top Condition / Qualifier Box
                if !action.qualifierOrCondition.isEmpty {
                    Text(action.qualifierOrCondition)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(vm.theme.textColor)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .frame(minWidth: 90)
                        .background(vm.theme.stepFillColor)
                        .overlay(
                            Rectangle().stroke(isSelected ? Color.accentColor : vm.theme.strokeColor, lineWidth: 1.5)
                        )
                }

                // Main Variable Box
                Text(action.variable)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(vm.theme.textColor)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .frame(minWidth: 90)
                    .background(vm.theme.stepFillColor)
                    .overlay(
                        Rectangle().stroke(isSelected ? Color.accentColor : vm.theme.strokeColor, lineWidth: isSelected ? 2.5 : 2)
                    )
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 6)
            .onTapGesture {
                vm.selectAction(id: action.id, stepId: stepId)
                editingAction = action
                editingActionStepId = stepId
                showActionInspector = true
            }

            // Comment to the right in quotes
            if !action.comment.isEmpty {
                Text("„\(action.comment)“")
                    .font(.system(size: 13, weight: .regular))
                    .italic()
                    .foregroundStyle(vm.theme.secondaryTextColor)
                    .padding(.leading, 8)
            }
        }
    }

    // MARK: - Transition Node View

    private func transitionNodeView(_ trans: GrafcetTransition) -> some View {
        let center = GrafcetGrid.center(col: trans.col, row: trans.row)
        let isSelected = vm.selectedTransitionId == trans.id

        return HStack(spacing: 8) {
            // Transition Name (left): e.g. (1)
            if !trans.name.isEmpty {
                Text("(\(trans.name))")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(vm.theme.secondaryTextColor)
            }

            // Central Horizontal Bar
            Rectangle()
                .fill(isSelected ? Color.accentColor : vm.theme.transitionBarColor)
                .frame(width: 38, height: isSelected ? 4 : 3)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 6)

            // Transition Condition (right): e.g. B1*B2, 3s/X2, 1
            Text(trans.condition)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(vm.theme.textColor)
        }
        .position(x: center.x, y: center.y)
        .onTapGesture {
            vm.selectTransition(id: trans.id)
            editingTransition = trans
            showTransitionInspector = true
        }
    }

    // MARK: - Connection Lines Layer

    private func connectionLine(_ conn: GrafcetConnection) -> some View {
        let p1: CGPoint
        let p2: CGPoint

        if let fromStep = vm.steps.first(where: { $0.id == conn.fromId }) {
            p1 = CGPoint(x: GrafcetGrid.center(col: fromStep.col, row: fromStep.row).x,
                         y: GrafcetGrid.center(col: fromStep.col, row: fromStep.row).y + GrafcetGrid.stepSize / 2)
        } else if let fromTrans = vm.transitions.first(where: { $0.id == conn.fromId }) {
            p1 = GrafcetGrid.center(col: fromTrans.col, row: fromTrans.row)
        } else {
            return AnyView(EmptyView())
        }

        if let toStep = vm.steps.first(where: { $0.id == conn.toId }) {
            p2 = CGPoint(x: GrafcetGrid.center(col: toStep.col, row: toStep.row).x,
                         y: GrafcetGrid.center(col: toStep.col, row: toStep.row).y - GrafcetGrid.stepSize / 2)
        } else if let toTrans = vm.transitions.first(where: { $0.id == conn.toId }) {
            p2 = GrafcetGrid.center(col: toTrans.col, row: toTrans.row)
        } else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ZStack {
                switch conn.type {
                case .sequence:
                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                    }
                    .stroke(vm.theme.strokeColor, lineWidth: 2)

                case .orBranch, .orJoin:
                    Path { path in
                        let midY = (p1.y + p2.y) / 2
                        path.move(to: p1)
                        path.addLine(to: CGPoint(x: p1.x, y: midY))
                        path.addLine(to: CGPoint(x: p2.x, y: midY))
                        path.addLine(to: p2)
                    }
                    .stroke(vm.theme.strokeColor, lineWidth: 2)

                case .andSplit, .andJoin:
                    ZStack {
                        let midY = (p1.y + p2.y) / 2
                        let leftX = min(p1.x, p2.x) - 30
                        let rightX = max(p1.x, p2.x) + 30

                        // Parallel Double Bar
                        Path { path in
                            path.move(to: CGPoint(x: leftX, y: midY - 2.5))
                            path.addLine(to: CGPoint(x: rightX, y: midY - 2.5))
                            path.move(to: CGPoint(x: leftX, y: midY + 2.5))
                            path.addLine(to: CGPoint(x: rightX, y: midY + 2.5))
                        }
                        .stroke(vm.theme.strokeColor, lineWidth: 3)

                        // Connecting Lines
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: CGPoint(x: p1.x, y: midY - 2.5))
                            path.move(to: CGPoint(x: p2.x, y: midY + 2.5))
                            path.addLine(to: p2)
                        }
                        .stroke(vm.theme.strokeColor, lineWidth: 2)
                    }

                case .loopBack:
                    ZStack {
                        let loopX = min(p1.x, p2.x) - 70
                        Path { path in
                            path.move(to: p1)
                            path.addLine(to: CGPoint(x: loopX, y: p1.y))
                            path.addLine(to: CGPoint(x: loopX, y: p2.y))
                            path.addLine(to: p2)
                        }
                        .stroke(vm.theme.strokeColor, lineWidth: 2)

                        // Upward Arrowhead
                        let arrowY = (p1.y + p2.y) / 2
                        Path { path in
                            path.move(to: CGPoint(x: loopX, y: arrowY - 7))
                            path.addLine(to: CGPoint(x: loopX - 5, y: arrowY + 5))
                            path.addLine(to: CGPoint(x: loopX + 5, y: arrowY + 5))
                            path.closeSubpath()
                        }
                        .fill(vm.theme.strokeColor)
                    }

                case .jump:
                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: CGPoint(x: p1.x + 30, y: p1.y))
                    }
                    .stroke(vm.theme.strokeColor, lineWidth: 2)
                }
            }
        )
    }

    // MARK: - Floating Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Quick Step + Transition
            Button {
                if let selected = vm.steps.first(where: { $0.id == vm.selectedStepId }) {
                    vm.appendTransitionBelow(step: selected)
                } else {
                    _ = vm.addStep()
                }
            } label: {
                Label(vm.selectedStepId != nil ? "Transition +" : "Schritt +", systemImage: "plus.square")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)

            // Add Action to Selected Step
            if let stepId = vm.selectedStepId {
                Button {
                    vm.addAction(to: stepId)
                } label: {
                    Label("Aktion +", systemImage: "rectangle.badge.plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }

            // Quick Step below selected transition
            if let trans = vm.transitions.first(where: { $0.id == vm.selectedTransitionId }) {
                Button {
                    vm.appendStepBelow(transition: trans)
                } label: {
                    Label("Schritt darunter +", systemImage: "arrow.down.square")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
            }

            // Zoom Reset
            Button {
                withAnimation(.spring()) {
                    vm.zoomScale = 1.0
                    vm.panOffset = .zero
                }
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    // MARK: - Export Operations

    private func exportImage() {
        let img = vm.renderToImage()
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        onExportImage?(img)
        showToast("In Fotos gespeichert!")
    }

    private func shareImage() {
        let img = vm.renderToImage()
        let av = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            av.popoverPresentationController?.sourceView = root.view
            root.present(av, animated: true)
        }
    }

    private func showToast(_ text: String) {
        exportToastText = text
        withAnimation { showExportSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showExportSuccess = false }
        }
    }
}

// MARK: - Grid Background View

struct GrafcetGridBackgroundView: View {
    var theme: GrafcetTheme = .light

    var body: some View {
        Canvas { ctx, size in
            // Background fill
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.canvasBackground))

            let step: CGFloat = 35
            var x: CGFloat = 17.5
            while x < size.width {
                var y: CGFloat = 17.5
                while y < size.height {
                    let dot = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    ctx.fill(dot, with: .color(theme.gridDotColor))
                    y += step
                }
                x += step
            }
        }
    }
}

// MARK: - Step Inspector Sheet

struct GrafcetStepInspectorSheet: View {
    @State var step: GrafcetStep
    let onSave: (GrafcetStep) -> Void
    let onDelete: () -> Void
    let onAddAction: () -> Void
    let onAppendTransition: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Schritt-Eigenschaften") {
                    HStack {
                        Text("Schrittnummer")
                        Spacer()
                        TextField("z.B. 1, 2, 3a", text: $step.number)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.bold))
                    }

                    Picker("Schritt-Typ", selection: $step.type) {
                        ForEach(GrafcetStepType.allCases) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }

                    Toggle("Initialschritt einer Einschließung (*)", isOn: $step.isInitialOfEnclosure)

                    if step.type == .enclosing {
                        TextField("Name der Einschließung", text: $step.enclosingTitle)
                    }
                }

                Section("Raster-Position") {
                    Stepper("Spalte: \(step.col)", value: $step.col, in: 1...8)
                    Stepper("Zeile: \(step.row)", value: $step.row, in: 0...40)
                }

                Section("Schnell-Aktionen") {
                    Button {
                        onAppendTransition()
                        dismiss()
                    } label: {
                        Label("Transition darunter einfügen", systemImage: "plus.forwardslash.minus")
                    }

                    Button {
                        onAddAction()
                        dismiss()
                    } label: {
                        Label("Aktion rechts anhängen", systemImage: "rectangle.badge.plus")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Schritt löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Schritt \(step.number) bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSave(step)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Transition Inspector Sheet

struct GrafcetTransitionInspectorSheet: View {
    @State var transition: GrafcetTransition
    let onSave: (GrafcetTransition) -> Void
    let onDelete: () -> Void
    let onAppendStep: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Transitions-Eigenschaften") {
                    HStack {
                        Text("Transitionsname (optional)")
                        Spacer()
                        TextField("z.B. 1, 2", text: $transition.name)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transitionsbedingung")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("z.B. B1*B2, 3s/X2, 1", text: $transition.condition)
                            .font(.body.weight(.bold))
                            .textFieldStyle(.roundedBorder)

                        // Quick Insert Toolbar
                        HStack(spacing: 8) {
                            quickInsertButton("*", label: "UND (*)")
                            quickInsertButton("+", label: "ODER (+)")
                            quickInsertButton("1", label: "TRUE (1)")
                            quickInsertButton("↑", label: "↑ Flanke")
                            quickInsertButton("!", label: "Negation (!)")
                            quickInsertButton("3s/X", label: "Zeit")
                        }
                    }
                }

                Section("Raster-Position") {
                    Stepper("Spalte: \(transition.col)", value: $transition.col, in: 1...8)
                    Stepper("Zeile: \(transition.row)", value: $transition.row, in: 0...40)
                }

                Section("Schnell-Aktionen") {
                    Button {
                        onAppendStep()
                        dismiss()
                    } label: {
                        Label("Schritt darunter einfügen", systemImage: "arrow.down.square")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Transition löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Transition bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSave(transition)
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickInsertButton(_ text: String, label: String) -> some View {
        Button {
            if transition.condition == "1" {
                transition.condition = text
            } else {
                transition.condition += text
            }
        } label: {
            Text(label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Inspector Sheet

struct GrafcetActionInspectorSheet: View {
    @State var action: GrafcetAction
    let onSave: (GrafcetAction) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Aktionstyp nach DIN EN 60848") {
                    Picker("Typ", selection: $action.type) {
                        ForEach(GrafcetActionType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .onChange(of: action.type) { _, newType in
                        if action.qualifierOrCondition.isEmpty || action.qualifierOrCondition == action.type.defaultQualifier {
                            action.qualifierOrCondition = newType.defaultQualifier
                        }
                    }

                    Text(action.type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Befehl & Zuweisung") {
                    HStack {
                        Text("Variable / Zuweisung")
                        Spacer()
                        TextField("z.B. M1, M1:=1, Motor M2", text: $action.variable)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                    }

                    if action.type != .continuous {
                        HStack {
                            Text("Bedingung / Zeit / Qualifizierer")
                            Spacer()
                            TextField("z.B. B2, 1s/X2, ↑B3", text: $action.qualifierOrCondition)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    HStack {
                        Text("Kommentar (optional)")
                        Spacer()
                        TextField("z.B. Band läuft", text: $action.comment)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Aktion löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Aktion bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSave(action)
                        dismiss()
                    }
                }
            }
        }
    }
}
