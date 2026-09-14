import Foundation

struct DocumentItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var type: ItemType
    var modifiedAt: Date
    var syncStatus: SyncStatus

    var isFolder: Bool { type == .folder }

    var systemImage: String {
        switch type {
        case .folder:     return "folder.fill"
        case .pdf:        return "doc.richtext.fill"
        case .note:       return "note.text"
        case .pap:        return "arrow.triangle.branch"
        case .whiteboard: return "rectangle.and.pencil.and.ellipsis"
        case .mindmap:    return "brain"
        }
    }

    /// True for any document type that opens in the canvas/notebook area
    var isDocument: Bool {
        switch type {
        case .folder, .pdf: return false
        case .note, .pap, .whiteboard, .mindmap: return true
        }
    }

    enum ItemType: String {
        case folder, pdf, note, pap, whiteboard, mindmap

        var collabDocumentType: CollabDocumentType? {
            switch self {
            case .note: return .note
            case .whiteboard: return .whiteboard
            case .pap: return .pap
            case .mindmap: return .mindmap
            case .folder, .pdf: return nil
            }
        }
    }

    enum SyncStatus: Equatable {
        case local, synced, pending, conflict, error(String)

        var systemImage: String {
            switch self {
            case .local:    return ""
            case .synced:   return "checkmark.icloud"
            case .pending:  return "arrow.triangle.2.circlepath.icloud"
            case .conflict: return "exclamationmark.icloud"
            case .error:    return "xmark.icloud"
            }
        }
    }

    static func == (lhs: DocumentItem, rhs: DocumentItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
