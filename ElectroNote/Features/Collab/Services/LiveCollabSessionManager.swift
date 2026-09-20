import Foundation
import Combine
import UIKit
import Network

enum CollabSessionState: Equatable {
    case idle
    case hosting
    case connected
    case error(String)
}

struct DocumentSwitchRequest: Equatable {
    let id: UUID = UUID()
    let title: String
    let type: CollabDocumentType
}

@MainActor
final class LiveCollabSessionManager: ObservableObject {
    static let shared = LiveCollabSessionManager()

    @Published var sessionState: CollabSessionState = .idle
    @Published var connectedPeers: [CollabPeer] = []
    @Published var hostIP: String = ""
    @Published var hostPort: UInt16 = 8765
    @Published var roomCode: String = ""
    @Published var discoveredRooms: [DiscoveredRoom] = []
    @Published var activeDocumentType: CollabDocumentType = .note
    @Published var autoOpenRequestedType: CollabDocumentType? = nil
    @Published var remoteDocumentSwitchRequest: DocumentSwitchRequest? = nil
    @Published var activeDocumentTitle: String = "Live-Zusammenarbeit"
    @Published var myPeer: CollabPeer

    static func cleanDocumentTitle(_ title: String) -> String {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for ext in [".enote", ".epap", ".ewb", ".emm", ".egrafcet", ".pdf"] {
            if clean.hasSuffix(ext) {
                clean = String(clean.dropLast(ext.count))
            }
        }
        return clean.isEmpty ? "Live-Zusammenarbeit" : clean
    }

    static func titlesMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b else { return true }
        let cleanA = cleanDocumentTitle(a)
        let cleanB = cleanDocumentTitle(b)
        if cleanA.isEmpty || cleanB.isEmpty { return true }
        return cleanA.localizedCaseInsensitiveCompare(cleanB) == .orderedSame
    }

    // Document hooks
    var onProvideSnapshot: (() -> (docJson: String?, drawingJson: String?, pkDrawingBase64: String?, documentTitle: String?, pdfAssets: [String: String]?))?
    var onApplySnapshot: ((String?, String?, String?, [String: String]?) -> Void)? {
        didSet {
            if let onApplySnapshot = onApplySnapshot, (pendingDocSnapshot != nil || pendingDrawingSnapshot != nil || pendingPkDrawingBase64 != nil || pendingPdfAssets != nil) {
                print("[CollabSession] Replaying cached snapshot (\(pendingSnapshotDocTitle ?? "")) to newly attached onApplySnapshot")
                let doc = pendingDocSnapshot
                let drawing = pendingDrawingSnapshot
                let pk = pendingPkDrawingBase64
                let pdfs = pendingPdfAssets
                pendingDocSnapshot = nil
                pendingDrawingSnapshot = nil
                pendingPkDrawingBase64 = nil
                pendingPdfAssets = nil
                pendingSnapshotDocTitle = nil
                onApplySnapshot(doc, drawing, pk, pdfs)
            }
        }
    }
    private var pendingSnapshotDocTitle: String?
    private var pendingDocSnapshot: String?
    private var pendingDrawingSnapshot: String?
    private var pendingPkDrawingBase64: String?
    private var pendingPdfAssets: [String: String]?

    var onRemoteStrokeReceived: ((PortableStrokeDTO, String?, String?) -> Void)?
    var onRemoteStrokesCleared: ((String?) -> Void)?
    var onRemoteElementUpsert: ((String) -> Void)?
    var onRemoteElementMoved: ((String, Double, Double) -> Void)?
    var onRemoteElementDeleted: ((String) -> Void)?
    var onRemoteStickyNoteUpsert: ((String) -> Void)?
    var onRemoteStickyNoteDeleted: ((String) -> Void)?
    var onRemoteDiagramAction: ((CollabMessage) -> Void)?
    var onRemoteCursorMoved: ((CollabCursor) -> Void)?

    private let server = LiveCollabServer()
    private let client = LiveCollabClient()

    private init() {
        let deviceName = UIDevice.current.name
        let randomColors = ["#007AFF", "#34C759", "#FF9500", "#AF52DE", "#FF2D55", "#5856D6"]
        let color = randomColors.randomElement() ?? "#007AFF"
        self.myPeer = CollabPeer(id: UUID().uuidString, name: deviceName, colorHex: color, isHost: false)

        setupCallbacks()
    }

    private func setupCallbacks() {
        server.onMessageReceived = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleIncomingMessage(message)
            }
        }

        server.onPeerListChanged = { [weak self] peers in
            Task { @MainActor [weak self] in
                self?.connectedPeers = peers
            }
        }

        server.onSnapshotNeeded = { [weak self] in
            if Thread.isMainThread {
                return self?.onProvideSnapshot?() ?? (nil, nil, nil, nil, nil)
            } else {
                return DispatchQueue.main.sync {
                    return self?.onProvideSnapshot?() ?? (nil, nil, nil, nil, nil)
                }
            }
        }

        client.onMessageReceived = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleIncomingMessage(message)
            }
        }

        client.onConnectedChanged = { [weak self] connected in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if connected {
                    self.sessionState = .connected
                    self.autoOpenRequestedType = self.activeDocumentType
                    let title = Self.cleanDocumentTitle(self.activeDocumentTitle)
                    self.remoteDocumentSwitchRequest = DocumentSwitchRequest(title: title, type: self.activeDocumentType)
                } else if case .connected = self.sessionState {
                    self.sessionState = .idle
                    self.connectedPeers = []
                    self.autoOpenRequestedType = nil
                    self.remoteDocumentSwitchRequest = nil
                }
            }
        }

        client.onDiscoveredRoomsChanged = { [weak self] rooms in
            Task { @MainActor [weak self] in
                self?.discoveredRooms = rooms
            }
        }
    }

    // MARK: - Hosting Session

    func startHosting(documentName: String, documentType: CollabDocumentType) {
        leaveSession()
        let cleanName = Self.cleanDocumentTitle(documentName)
        activeDocumentType = documentType
        activeDocumentTitle = cleanName
        myPeer.isHost = true

        do {
            try server.start(hostPeer: myPeer, documentType: documentType, roomName: "ElectroNote - \(cleanName)")
            hostIP = server.localIP
            hostPort = server.port
            roomCode = generateRoomCode(port: server.port)
            sessionState = .hosting
            connectedPeers = [myPeer]
            autoOpenRequestedType = documentType
            remoteDocumentSwitchRequest = DocumentSwitchRequest(title: cleanName, type: documentType)
        } catch {
            sessionState = .error(error.localizedDescription)
        }
    }

    // MARK: - Joining Session

    func startBrowsingRooms() {
        client.startBrowsing()
    }

    func stopBrowsingRooms() {
        client.stopBrowsing()
    }

    func joinSession(endpoint: NWEndpoint, documentType: CollabDocumentType) {
        leaveSession()
        activeDocumentType = documentType
        myPeer.isHost = false
        client.connect(endpoint: endpoint, localPeer: myPeer, documentType: documentType)
    }

    func joinSession(host: String, port: UInt16, documentType: CollabDocumentType) {
        leaveSession()
        activeDocumentType = documentType
        myPeer.isHost = false
        hostIP = host
        hostPort = port

        client.connect(host: host, port: port, localPeer: myPeer, documentType: documentType)
    }

    func leaveSession() {
        if case .hosting = sessionState {
            server.stop()
        } else if case .connected = sessionState {
            client.disconnect()
        }
        client.stopBrowsing()
        sessionState = .idle
        connectedPeers = []
        autoOpenRequestedType = nil
        remoteDocumentSwitchRequest = nil
        pendingDocSnapshot = nil
        pendingDrawingSnapshot = nil
        pendingPkDrawingBase64 = nil
        pendingPdfAssets = nil
        pendingSnapshotDocTitle = nil
    }

    func requestSnapshot() {
        let msg = CollabMessage(
            type: .snapshotRequest,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType
        )
        dispatchMessage(msg)
    }

    // MARK: - Broadcasting Actions

    func sendStroke(_ stroke: PortableStrokeDTO, pkStrokeBase64: String? = nil, documentTitle: String? = nil) {
        let title = documentTitle ?? activeDocumentTitle
        let cleanTitle = Self.cleanDocumentTitle(title)
        let msg = CollabMessage(
            type: .strokeAdded,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            documentTitle: cleanTitle,
            stroke: stroke,
            pkStrokeData: pkStrokeBase64
        )
        dispatchMessage(msg)
    }

    func sendStrokesCleared(documentTitle: String? = nil) {
        let title = documentTitle ?? activeDocumentTitle
        let cleanTitle = Self.cleanDocumentTitle(title)
        let msg = CollabMessage(
            type: .strokesCleared,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            documentTitle: cleanTitle
        )
        dispatchMessage(msg)
    }

    func switchDocument(title: String, type: CollabDocumentType) {
        guard sessionState == .hosting || sessionState == .connected else { return }
        let cleanTitle = Self.cleanDocumentTitle(title)
        guard !Self.titlesMatch(activeDocumentTitle, cleanTitle) || activeDocumentType != type else { return }
        print("[CollabSession] switchDocument: \(cleanTitle) (\(type))")
        activeDocumentTitle = cleanTitle
        activeDocumentType = type

        // Invalidate old snapshot callbacks and pending data from previous document
        onApplySnapshot = nil
        onProvideSnapshot = nil
        pendingDocSnapshot = nil
        pendingDrawingSnapshot = nil
        pendingPkDrawingBase64 = nil
        pendingPdfAssets = nil
        pendingSnapshotDocTitle = nil

        if sessionState == .hosting {
            server.documentType = type
        }
        let msg = CollabMessage(
            type: .documentSwitched,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: type,
            documentTitle: cleanTitle
        )
        dispatchMessage(msg)
    }

    func broadcastHostSnapshot(docJson: String?, drawingJson: String?, pkDrawingBase64: String?, documentTitle: String?, pdfAssets: [String: String]? = nil) {
        guard sessionState == .hosting, !connectedPeers.isEmpty else { return }
        let cleanTitle = Self.cleanDocumentTitle(documentTitle ?? activeDocumentTitle)
        server.broadcastSnapshot(
            docJson: docJson,
            drawingJson: drawingJson,
            pkDrawingBase64: pkDrawingBase64,
            documentTitle: cleanTitle,
            pdfAssets: pdfAssets
        )
    }

    func sendFullDrawingSync(pkDrawingBase64: String?, portableStrokes: [PortableStrokeDTO]? = nil, documentTitle: String? = nil) {
        let title = documentTitle ?? activeDocumentTitle
        let cleanTitle = Self.cleanDocumentTitle(title)
        let strokesJson = (try? JSONEncoder().encode(portableStrokes)).flatMap { String(data: $0, encoding: .utf8) }
        let msg = CollabMessage(
            type: .snapshotResponse,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            documentTitle: cleanTitle,
            documentSnapshotJson: nil,
            drawingSnapshotJson: strokesJson,
            pkDrawingData: pkDrawingBase64
        )
        dispatchMessage(msg)
    }

    func sendElementUpsert(elementJson: String, elementId: String) {
        let msg = CollabMessage(
            type: .elementUpsert,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementJson: elementJson,
            elementId: elementId
        )
        dispatchMessage(msg)
    }

    func sendElementMoved(elementId: String, x: Double, y: Double) {
        let msg = CollabMessage(
            type: .elementMoved,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementId: elementId,
            position: CollabPoint(x: x, y: y)
        )
        dispatchMessage(msg)
    }

    func sendElementDeleted(elementId: String) {
        let msg = CollabMessage(
            type: .elementDeleted,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementId: elementId
        )
        dispatchMessage(msg)
    }

    func sendStickyNoteUpsert(noteJson: String, noteId: String) {
        let msg = CollabMessage(
            type: .stickyNoteUpsert,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementId: noteId,
            stickyNoteJson: noteJson
        )
        dispatchMessage(msg)
    }

    func sendStickyNoteDeleted(noteId: String) {
        let msg = CollabMessage(
            type: .stickyNoteDeleted,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementId: noteId
        )
        dispatchMessage(msg)
    }

    func sendDiagramAction(action: CollabActionType, nodeJson: String? = nil, connectionJson: String? = nil, elementId: String? = nil, position: CollabPoint? = nil) {
        let msg = CollabMessage(
            type: action,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            elementId: elementId,
            position: position,
            nodeJson: nodeJson,
            connectionJson: connectionJson
        )
        dispatchMessage(msg)
    }

    func sendCursor(point: CGPoint) {
        let cursor = CollabCursor(x: Double(point.x), y: Double(point.y), name: myPeer.name, colorHex: myPeer.colorHex)
        let msg = CollabMessage(
            type: .cursorMoved,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            cursor: cursor
        )
        dispatchMessage(msg)
    }

    private func dispatchMessage(_ msg: CollabMessage) {
        if case .hosting = sessionState {
            server.broadcast(message: msg)
        } else if case .connected = sessionState {
            client.send(message: msg)
        }
    }

    // MARK: - Incoming Message Handler

    private func handleIncomingMessage(_ message: CollabMessage) {
        switch message.type {
        case .roomState:
            if let peers = message.peers {
                connectedPeers = peers
            }

        case .snapshotResponse:
            let cleanTitle = Self.cleanDocumentTitle(message.documentTitle ?? self.activeDocumentTitle)
            print("[CollabSession] Received snapshotResponse for type: \(message.documentType), title: \(cleanTitle)")
            let docChanged = (!Self.titlesMatch(self.activeDocumentTitle, cleanTitle) || self.activeDocumentType != message.documentType)
            self.activeDocumentType = message.documentType
            self.activeDocumentTitle = cleanTitle
            self.autoOpenRequestedType = message.documentType

            if docChanged {
                self.onApplySnapshot = nil
                self.pendingSnapshotDocTitle = cleanTitle
                self.pendingDocSnapshot = message.documentSnapshotJson
                self.pendingDrawingSnapshot = message.drawingSnapshotJson
                self.pendingPkDrawingBase64 = message.pkDrawingData
                self.pendingPdfAssets = message.pdfAssets
                self.remoteDocumentSwitchRequest = DocumentSwitchRequest(title: cleanTitle, type: message.documentType)
            } else if let onApplySnapshot = self.onApplySnapshot {
                print("[CollabSession] Applying snapshot immediately to attached handler for \(cleanTitle)")
                onApplySnapshot(message.documentSnapshotJson, message.drawingSnapshotJson, message.pkDrawingData, message.pdfAssets)
                self.pendingDocSnapshot = nil
                self.pendingDrawingSnapshot = nil
                self.pendingPkDrawingBase64 = nil
                self.pendingPdfAssets = nil
                self.pendingSnapshotDocTitle = nil
            } else {
                print("[CollabSession] Caching snapshot until view mounts for \(cleanTitle)")
                self.pendingSnapshotDocTitle = cleanTitle
                self.pendingDocSnapshot = message.documentSnapshotJson
                self.pendingDrawingSnapshot = message.drawingSnapshotJson
                self.pendingPkDrawingBase64 = message.pkDrawingData
                self.pendingPdfAssets = message.pdfAssets
            }

        case .snapshotRequest:
            if let provider = self.onProvideSnapshot {
                let snapshots = provider()
                let cleanTitle = Self.cleanDocumentTitle(snapshots.documentTitle ?? self.activeDocumentTitle)
                let msg = CollabMessage(
                    type: .snapshotResponse,
                    senderId: myPeer.id,
                    senderName: myPeer.name,
                    documentType: activeDocumentType,
                    documentTitle: cleanTitle,
                    documentSnapshotJson: snapshots.docJson,
                    drawingSnapshotJson: snapshots.drawingJson,
                    pkDrawingData: snapshots.pkDrawingBase64,
                    pdfAssets: snapshots.pdfAssets
                )
                dispatchMessage(msg)
            }

        case .documentSwitched:
            let cleanTitle = Self.cleanDocumentTitle(message.documentTitle ?? "Live-Zusammenarbeit")
            print("[CollabSession] Remote switched document to: \(cleanTitle) (\(message.documentType))")
            if !Self.titlesMatch(self.activeDocumentTitle, cleanTitle) || self.activeDocumentType != message.documentType {
                self.onApplySnapshot = nil
                self.onProvideSnapshot = nil
                self.pendingDocSnapshot = nil
                self.pendingDrawingSnapshot = nil
                self.pendingPkDrawingBase64 = nil
                self.pendingSnapshotDocTitle = nil
            }
            self.activeDocumentType = message.documentType
            self.activeDocumentTitle = cleanTitle
            self.autoOpenRequestedType = message.documentType
            self.remoteDocumentSwitchRequest = DocumentSwitchRequest(title: cleanTitle, type: message.documentType)

        case .strokeAdded:
            let fallbackStroke = message.stroke ?? PortableStrokeDTO(color: -16777216, width: 2.0, points: [])
            if message.stroke != nil || message.pkStrokeData != nil {
                if let docTitle = message.documentTitle, !docTitle.isEmpty, !Self.titlesMatch(docTitle, self.activeDocumentTitle) {
                    let clean = Self.cleanDocumentTitle(docTitle)
                    print("[CollabSession] Received stroke for different document: '\(clean)' (current: '\(self.activeDocumentTitle)'), triggering switch")
                    self.activeDocumentTitle = clean
                    self.activeDocumentType = message.documentType
                    self.autoOpenRequestedType = message.documentType
                    self.remoteDocumentSwitchRequest = DocumentSwitchRequest(title: clean, type: message.documentType)
                }
                onRemoteStrokeReceived?(fallbackStroke, message.pkStrokeData, message.documentTitle)
            }

        case .strokesCleared:
            onRemoteStrokesCleared?(message.documentTitle)

        case .elementUpsert:
            if let json = message.elementJson {
                onRemoteElementUpsert?(json)
            }

        case .elementMoved:
            if let id = message.elementId, let pt = message.position {
                onRemoteElementMoved?(id, pt.x, pt.y)
            }

        case .elementDeleted:
            if let id = message.elementId {
                onRemoteElementDeleted?(id)
            }

        case .stickyNoteUpsert:
            if let json = message.stickyNoteJson {
                onRemoteStickyNoteUpsert?(json)
            }

        case .stickyNoteDeleted:
            if let id = message.elementId {
                onRemoteStickyNoteDeleted?(id)
            }

        case .nodeAdded, .nodeMoved, .nodeUpdated, .nodeDeleted, .connectionAdded, .connectionDeleted:
            onRemoteDiagramAction?(message)

        case .cursorMoved:
            if let cursor = message.cursor {
                onRemoteCursorMoved?(cursor)
            }

        default:
            break
        }
    }

    private func generateRoomCode(port: UInt16) -> String {
        let lastDigits = Int(port % 1000)
        let randomNum = Int.random(in: 100...999)
        return "\(randomNum)-\(String(format: "%03d", lastDigits))"
    }
}
