import SwiftUI
import Combine
import PencilKit

enum CanvasToolType: String, CaseIterable, Identifiable {
    case pen        = "Stift"
    case marker     = "Marker"
    case pencil     = "Bleistift"
    case eraser     = "Radierer"
    case lasso      = "Lasso"
    case textSelect = "Text"
    case pan        = "Verschieben"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .pen:        return "pencil.tip"
        case .marker:     return "highlighter"
        case .pencil:     return "pencil"
        case .eraser:     return "eraser.fill"
        case .lasso:      return "lasso"
        case .textSelect: return "text.viewfinder"
        case .pan:        return "hand.draw"
        }
    }
}

func makePKTool(tool: CanvasToolType, color: Color, width: CGFloat, eraserType: PKEraserTool.EraserType, darkDrawingMode: Bool = false) -> PKTool {
    let uiColor: UIColor
    if color == .black {
        uiColor = .black
    } else if color == .white {
        uiColor = .white
    } else {
        uiColor = UIColor(color)
    }
    switch tool {
    case .pen, .textSelect, .pan:
        return PKInkingTool(.pen, color: uiColor, width: width)
    case .marker:
        return PKInkingTool(.marker, color: uiColor, width: max(width * 3.0, 10))
    case .pencil:
        return PKInkingTool(.pencil, color: uiColor, width: max(width * 1.5, 2))
    case .eraser:
        return PKEraserTool(eraserType)
    case .lasso:
        return PKLassoTool()
    }
}

@MainActor
final class InfiniteNotebookViewModel: ObservableObject {

    // MARK: - Pen Toolbar State
    @Published var lastDrawingTool: CanvasToolType = .pen
    @Published var activeTool: CanvasToolType = .pen {
        didSet {
            if activeTool != .pan && activeTool != .lasso && activeTool != .textSelect {
                lastDrawingTool = activeTool
            }
            applyCurrentTool()
        }
    }
    @Published var selectedColor: Color = .black {
        didSet { applyCurrentTool() }
    }
    @Published var selectedWidth: CGFloat = 3.0 {
        didSet { applyCurrentTool() }
    }
    @Published var eraserType: PKEraserTool.EraserType = .vector {
        didSet { applyCurrentTool() }
    }
    @Published var pendingPKTool: PKTool? = nil

    // MARK: - Published state (synced to UIKit VC)
    @Published var pencilOnly:      Bool            = true
    @Published var background:      BackgroundStyle  = .grid
    @Published var lineSpacing:     LineSpacing      = .medium
    @Published var mathEnabled:       Bool            = false
    @Published var darkDrawingMode:   Bool            = false {
        didSet { applyCurrentTool() }
    }
    @Published var shapeSnapEnabled:  Bool            = false
    @Published var rulerActive:       Bool            = false

    func togglePanMode() {
        if activeTool == .pan {
            activeTool = lastDrawingTool
        } else {
            if activeTool != .lasso && activeTool != .textSelect {
                lastDrawingTool = activeTool
            }
            activeTool = .pan
        }
    }

    func applyCurrentTool() {
        if activeTool == .pan || activeTool == .lasso || activeTool == .textSelect {
            pendingPKTool = nil
            return
        }
        pendingPKTool = makePKTool(tool: activeTool, color: selectedColor, width: selectedWidth, eraserType: eraserType, darkDrawingMode: darkDrawingMode)
    }

    init() {
        applyCurrentTool()
    }

    // MARK: - UI state
    @Published var saveState:    SaveState = .saved
    @Published var showPDFPicker: Bool     = false
    @Published var showPlotter:   Bool     = false
    @Published var pendingPDFURL: URL?     = nil
    @Published var pendingImage:  UIImage? = nil
    @Published var triggerHandwritingRecognition: Bool = false
    @Published var triggerMathRecognition:        Bool = false
    @Published var triggerPaste:                  Bool = false
    @Published var triggerAddStickyNote:          Bool = false
    @Published var triggerAddBookmark:            Bool = false
    @Published var triggerShowBookmarks:          Bool = false
    @Published var showPAP:                       Bool = false
    @Published var showMindMap:                   Bool = false
    @Published var showWhiteboard:                Bool = false
    @Published var showCircuitPicker:             Bool = false
    @Published var showElektroSim:                Bool = false
    @Published var showCameraPhoto:               Bool = false
    @Published var showDocumentScanner:           Bool = false
    @Published var showCameraVideo:               Bool = false
    @Published var showYouTubeEmbed:              Bool = false
    @Published var pendingMediaInsertion:         MediaInsertion? = nil
    @Published var activePlaybackMedia:           MediaPlaybackItem? = nil
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
