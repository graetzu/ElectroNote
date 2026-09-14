import Foundation

// MARK: - Document Types

enum CollabDocumentType: String, Codable {
    case note
    case whiteboard
    case pap
    case mindmap

    var browserDocumentType: DocumentType {
        switch self {
        case .note: return .notebook
        case .whiteboard: return .whiteboard
        case .pap: return .pap
        case .mindmap: return .mindmap
        }
    }
}

// MARK: - Action Types

enum CollabActionType: String, Codable {
    // Session lifecycle
    case join
    case roomState
    case snapshotRequest
    case snapshotResponse
    case leave

    // Canvas actions (Notebook & Whiteboard)
    case strokeAdded
    case strokesCleared
    case elementUpsert
    case elementMoved
    case elementDeleted
    case stickyNoteUpsert
    case stickyNoteDeleted

    // Diagram actions (PAP & MindMap)
    case nodeAdded
    case nodeMoved
    case nodeUpdated
    case nodeDeleted
    case connectionAdded
    case connectionDeleted

    // Presence
    case cursorMoved
}

// MARK: - Peer Information

struct CollabPeer: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var colorHex: String
    var isHost: Bool
}

// MARK: - Point & Cursor

struct CollabPoint: Codable {
    var x: Double
    var y: Double
}

struct CollabCursor: Codable {
    var x: Double
    var y: Double
    var name: String
    var colorHex: String
}

// MARK: - Envelope Message

struct CollabMessage: Codable {
    var id: String = UUID().uuidString
    var type: CollabActionType
    var senderId: String
    var senderName: String
    var documentType: CollabDocumentType
    var timestamp: Double = Date().timeIntervalSince1970

    // Optional Payloads
    var peer: CollabPeer?
    var peers: [CollabPeer]?
    var documentSnapshotJson: String?
    var drawingSnapshotJson: String?
    var stroke: PortableStrokeDTO?
    var elementJson: String?
    var elementId: String?
    var position: CollabPoint?
    var stickyNoteJson: String?
    var nodeJson: String?
    var connectionJson: String?
    var cursor: CollabCursor?
}
