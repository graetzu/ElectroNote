import Foundation
import SwiftUI

enum SyncProvider: String, CaseIterable, Identifiable, Codable {
    case none        = "none"
    case nextcloud   = "nextcloud"
    case icloud      = "icloud"
    case googleDrive = "googleDrive"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:        return "Nur Lokal (Kein Sync)"
        case .nextcloud:   return "Nextcloud"
        case .icloud:      return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        }
    }

    var shortName: String {
        switch self {
        case .none:        return "Lokal"
        case .nextcloud:   return "Nextcloud"
        case .icloud:      return "iCloud"
        case .googleDrive: return "Google Drive"
        }
    }

    var icon: String {
        switch self {
        case .none:        return "internaldrive"
        case .nextcloud:   return "externaldrive.connected.to.line.below"
        case .icloud:      return "icloud.fill"
        case .googleDrive: return "tray.and.arrow.up.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .none:        return .secondary
        case .nextcloud:   return Color(red: 0.0, green: 0.51, blue: 0.82)
        case .icloud:      return Color(red: 0.20, green: 0.60, blue: 1.0)
        case .googleDrive: return Color(red: 0.95, green: 0.65, blue: 0.15)
        }
    }
}
