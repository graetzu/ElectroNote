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
    @Published var myPeer: CollabPeer

    // Document hooks
    var onProvideSnapshot: (() -> (docJson: String?, drawingJson: String?))?
    var onApplySnapshot: ((String?, String?) -> Void)? {
        didSet {
            if let onApplySnapshot = onApplySnapshot, (pendingDocSnapshot != nil || pendingDrawingSnapshot != nil) {
                print("[CollabSession] Replaying cached snapshot to newly attached onApplySnapshot")
                let doc = pendingDocSnapshot
                let drawing = pendingDrawingSnapshot
                pendingDocSnapshot = nil
                pendingDrawingSnapshot = nil
                onApplySnapshot(doc, drawing)
            }
        }
    }
    private var pendingDocSnapshot: String?
    private var pendingDrawingSnapshot: String?

    var onRemoteStrokeReceived: ((PortableStrokeDTO) -> Void)?
    var onRemoteStrokesCleared: (() -> Void)?
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
                return self?.onProvideSnapshot?() ?? (nil, nil)
            } else {
                return DispatchQueue.main.sync {
                    return self?.onProvideSnapshot?() ?? (nil, nil)
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
                if connected {
                    self?.sessionState = .connected
                    self?.autoOpenRequestedType = self?.activeDocumentType
                } else if case .connected = self?.sessionState {
                    self?.sessionState = .idle
                    self?.connectedPeers = []
                    self?.autoOpenRequestedType = nil
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
        activeDocumentType = documentType
        myPeer.isHost = true

        do {
            try server.start(hostPeer: myPeer, documentType: documentType, roomName: "ElectroNote - \(documentName)")
            hostIP = server.localIP
            hostPort = server.port
            roomCode = generateRoomCode(port: server.port)
            sessionState = .hosting
            connectedPeers = [myPeer]
            autoOpenRequestedType = documentType
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
        pendingDocSnapshot = nil
        pendingDrawingSnapshot = nil
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

    func sendStroke(_ stroke: PortableStrokeDTO) {
        let msg = CollabMessage(
            type: .strokeAdded,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType,
            stroke: stroke
        )
        dispatchMessage(msg)
    }

    func sendStrokesCleared() {
        let msg = CollabMessage(
            type: .strokesCleared,
            senderId: myPeer.id,
            senderName: myPeer.name,
            documentType: activeDocumentType
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
            print("[CollabSession] Received snapshotResponse for type: \(message.documentType)")
            self.activeDocumentType = message.documentType
            self.autoOpenRequestedType = message.documentType
            if let onApplySnapshot = self.onApplySnapshot {
                print("[CollabSession] Applying snapshot immediately to attached handler")
                onApplySnapshot(message.documentSnapshotJson, message.drawingSnapshotJson)
                self.pendingDocSnapshot = nil
                self.pendingDrawingSnapshot = nil
            } else {
                print("[CollabSession] Caching snapshot until view mounts")
                self.pendingDocSnapshot = message.documentSnapshotJson
                self.pendingDrawingSnapshot = message.drawingSnapshotJson
            }

        case .strokeAdded:
            if let stroke = message.stroke {
                onRemoteStrokeReceived?(stroke)
            }

        case .strokesCleared:
            onRemoteStrokesCleared?()

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
