import SwiftUI
import Combine

@MainActor
final class InfiniteNotebookViewModel: ObservableObject {

    // MARK: - Published state (synced to UIKit VC)
    @Published var pencilOnly:   Bool          = true
    @Published var background:   BackgroundStyle = .grid
    @Published var mathEnabled:  Bool          = false

    // MARK: - UI state
    @Published var saveState:    SaveState     = .saved
    @Published var showPDFPicker:Bool          = false
    @Published var showPlotter:  Bool          = false
    @Published var pendingPDFURL: URL?         = nil
    @Published var pendingImage:  UIImage?     = nil
    @Published var triggerHandwritingRecognition: Bool = false

    enum SaveState: Equatable {
        case saved, saving, unsaved
        var label: String {
            switch self {
            case .saved:   return "Gespeichert"
            case .saving:  return "Speichern…"
            case .unsaved: return "Ungespeichert"
            }
        }
        var symbol: String {
            switch self {
            case .saved:   return "checkmark.circle"
            case .saving:  return "arrow.triangle.2.circlepath"
            case .unsaved: return "circle.dotted"
            }
        }
    }

    // MARK: - Autosave
    private var saveTimer: Timer?
    private weak var vcRef: InfiniteNotebookViewController?

    func attach(vc: InfiniteNotebookViewController) {
        vcRef = vc
        // Sync initial values from the loaded document
        background  = vc.document.background
        mathEnabled = vc.document.mathEnabled
        pencilOnly  = vc.pencilOnly
    }

    func markUnsaved() {
        saveState = .unsaved
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveState = .saving
                self?.vcRef?.save()
                self?.saveState = .saved
            }
        }
    }
}
