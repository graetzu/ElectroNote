import SwiftUI
import Combine

@MainActor
final class InfiniteNotebookViewModel: ObservableObject {

    // MARK: - Published state (synced to UIKit VC)
    @Published var pencilOnly:      Bool            = true
    @Published var background:      BackgroundStyle  = .grid
    @Published var lineSpacing:     LineSpacing      = .medium
    @Published var mathEnabled:       Bool            = false
    @Published var darkDrawingMode:   Bool            = false
    @Published var shapeSnapEnabled:  Bool            = true
    @Published var rulerActive:       Bool            = false

    // MARK: - UI state
    @Published var saveState:    SaveState = .saved
    @Published var showPDFPicker: Bool     = false
    @Published var showPlotter:   Bool     = false
    @Published var pendingPDFURL: URL?     = nil
    @Published var pendingImage:  UIImage? = nil
    @Published var triggerHandwritingRecognition: Bool = false
    @Published var triggerAddStickyNote:          Bool = false
    @Published var triggerAddBookmark:            Bool = false
    @Published var triggerShowBookmarks:          Bool = false
    @Published var showPAP:                       Bool = false
    @Published var showMindMap:                   Bool = false
    @Published var showWhiteboard:                Bool = false
    @Published var pendingInkPreset:              InkPreset? = nil
    @Published var showTextInsertion:             Bool = false
    @Published var pendingTextInsertion:          TypedTextInsertion? = nil

    // MARK: - Undo / Redo
    @Published var triggerUndo: Bool = false
    @Published var triggerRedo: Bool = false

    // MARK: - Native text input
    @Published var triggerNativeTextInput: Bool = false

    // MARK: - Export
    @Published var triggerExport:  Bool = false

    struct TypedTextInsertion {
        let text: String
        let fontSize: CGFloat
    }

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
        vcRef       = vc
        background       = vc.document.background
        lineSpacing      = vc.document.lineSpacing
        mathEnabled      = vc.document.mathEnabled
        darkDrawingMode  = vc.document.darkDrawingMode
        shapeSnapEnabled = vc.document.shapeSnapEnabled
        pencilOnly       = vc.pencilOnly
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
