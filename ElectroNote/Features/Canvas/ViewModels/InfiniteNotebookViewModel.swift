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
        case .textSelect: return "character.cursor.ibeam"
        case .pan:        return "hand.draw"
        }
    }
}

func makePKTool(
    tool: CanvasToolType,
    color: Color,
    width: CGFloat,
    eraserType: PKEraserTool.EraserType,
    eraserWidth: CGFloat = 16.0,
    darkDrawingMode: Bool = false
) -> PKTool {
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
        // PencilKit's eigene Marker-Transluzenz reicht bei breiten/überlappenden Strichen
        // nicht aus, um Text darunter lesbar zu halten — Alpha hier explizit selbst setzen.
        let markerColor = uiColor.withAlphaComponent(0.35)
        return PKInkingTool(.marker, color: markerColor, width: max(width * 2.5, 10))
    case .pencil:
        return PKInkingTool(.pencil, color: uiColor, width: max(width * 1.5, 2))
    case .eraser:
        return PKEraserTool(eraserType, width: eraserWidth)
    case .lasso:
        return PKLassoTool()
    }
}

@MainActor
final class InfiniteNotebookViewModel: ObservableObject {

    // MARK: - Pen Toolbar State & Per-Tool Memory
    @Published var penColor: Color = .black
    @Published var penWidth: CGFloat = 3.0

    @Published var markerColor: Color = .yellow
    @Published var markerWidth: CGFloat = 9.0

    @Published var pencilColor: Color = .gray
    @Published var pencilWidth: CGFloat = 1.5

    @Published var lastDrawingTool: CanvasToolType = .pen
    @Published var activeTool: CanvasToolType = .pen {
        willSet {
            saveCurrentToolState()
        }
        didSet {
            if activeTool != .pan && activeTool != .lasso && activeTool != .textSelect {
                lastDrawingTool = activeTool
            }
            restoreToolState(for: activeTool)
            applyCurrentTool()
        }
    }
    @Published var selectedColor: Color = .black {
        didSet {
            updateActiveToolColor(selectedColor)
            applyCurrentTool()
        }
    }
    @Published var selectedWidth: CGFloat = 3.0 {
        didSet {
            updateActiveToolWidth(selectedWidth)
            applyCurrentTool()
        }
    }
    @Published var eraserType: PKEraserTool.EraserType = .bitmap {
        didSet { applyCurrentTool() }
    }
    @Published var eraserWidth: CGFloat = 16.0 {
        didSet { applyCurrentTool() }
    }
    @Published var pendingPKTool: PKTool? = nil

    private func saveCurrentToolState() {
        switch activeTool {
        case .pen:
            penColor = selectedColor
            penWidth = selectedWidth
        case .marker:
            markerColor = selectedColor
            markerWidth = selectedWidth
        case .pencil:
            pencilColor = selectedColor
            pencilWidth = selectedWidth
        default:
            break
        }
    }

    private func restoreToolState(for tool: CanvasToolType) {
        switch tool {
        case .pen:
            selectedColor = penColor
            selectedWidth = penWidth
        case .marker:
            selectedColor = markerColor
            selectedWidth = markerWidth
        case .pencil:
            selectedColor = pencilColor
            selectedWidth = pencilWidth
        default:
            break
        }
    }

    private func updateActiveToolColor(_ color: Color) {
        switch activeTool {
        case .pen:
            penColor = color
        case .marker:
            markerColor = color
        case .pencil:
            pencilColor = color
        default:
            break
        }
    }

    private func updateActiveToolWidth(_ width: CGFloat) {
        switch activeTool {
        case .pen:
            penWidth = width
        case .marker:
            markerWidth = width
        case .pencil:
            pencilWidth = width
        default:
            break
        }
    }

    // MARK: - Published state (synced to UIKit VC)
    #if targetEnvironment(macCatalyst)
    @Published var pencilOnly:      Bool            = false
    #else
    @Published var pencilOnly:      Bool            = true
    #endif
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
        pendingPKTool = makePKTool(
            tool: activeTool,
            color: selectedColor,
            width: selectedWidth,
            eraserType: eraserType,
            eraserWidth: eraserWidth,
            darkDrawingMode: darkDrawingMode
        )
    }

    init() {
        #if targetEnvironment(macCatalyst)
        activeTool = .textSelect
        pencilOnly = false
        #endif
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
    @Published var triggerExport:          Bool = false
    @Published var showPDFExportSheet:     Bool = false
    @Published var isRangeExportModeActive: Bool = false
    @Published var exportRangeStartPage:   Int = 1
    @Published var exportRangeEndPage:     Int = 1
    @Published var exportTotalPages:       Int = 1
    @Published var exportCurrentPage:      Int = 1
    @Published var exportStartY:           CGFloat = 0
    @Published var exportEndY:             CGFloat = 1000

    func openPDFExportDialog() {
        if let vc = vcRef {
            exportTotalPages  = vc.totalPageCount
            exportCurrentPage = vc.currentPageNumber
            exportRangeStartPage = 1
            exportRangeEndPage   = vc.totalPageCount
        }
        showPDFExportSheet = true
    }

    func startRangeExportMode() {
        showPDFExportSheet = false
        isRangeExportModeActive = true
        vcRef?.enterRangeExportMode()
    }

    func cancelRangeExportMode() {
        isRangeExportModeActive = false
        vcRef?.exitRangeExportMode()
    }

    func snapRangeToPages() {
        vcRef?.snapRangeExportToPages()
    }

    func setRangeStartAtCurrentScroll() {
        vcRef?.setRangeExportStartAtCurrentScroll()
    }

    func setRangeEndAtCurrentScroll() {
        vcRef?.setRangeExportEndAtCurrentScroll()
    }

    func executeRangeExport() {
        isRangeExportModeActive = false
        vcRef?.exitRangeExportMode()
        vcRef?.presentExport(scope: .customArea(startY: exportStartY, endY: exportEndY), cropToExactHeight: true)
    }

    func executePDFExport(scope: NotebookPDFExportScope, cropToExactHeight: Bool = false) {
        showPDFExportSheet = false
        isRangeExportModeActive = false
        vcRef?.exitRangeExportMode()
        vcRef?.presentExport(scope: scope, cropToExactHeight: cropToExactHeight)
    }

    // MARK: - In-Canvas Find & Search
    @Published var showSearch:                 Bool = false {
        didSet {
            if !showSearch {
                searchQuery = ""
                searchMatchCount = 0
                currentSearchMatchIndex = 0
            }
        }
    }
    @Published var searchQuery:                String = ""
    @Published var searchMatchCount:           Int = 0
    @Published var currentSearchMatchIndex:    Int = 0
    @Published var triggerNextSearchMatch:     Bool = false
    @Published var triggerPreviousSearchMatch: Bool = false
    // MARK: - AI Assistant Sidebar
    @Published var showAISidebar: Bool = false
    // MARK: - Scientific Calculator
    @Published var showScientificCalculator: Bool = false

    func toggleScientificCalculator() {
        showScientificCalculator.toggle()
        if showScientificCalculator {
            ScientificCalculatorStore.shared.isMinimized = false
        }
    }

    // MARK: - Web Clipper & Screenshot
    @Published var showWebClipper: Bool = false
    @Published var pendingStickyNoteText: String? = nil

    func collectContextTextForAI() async -> String {
        guard let vc = vcRef else { return "" }
        return await vc.collectContextText()
    }

    func captureCurrentPageImageForAI() -> UIImage? {
        vcRef?.captureVisiblePageImage()
    }

    func renderCanvasSnapshotImage() -> UIImage? {
        vcRef?.renderCanvasSnapshotImage()
    }
    struct TypedTextInsertion {
        let text: String
        let fontSize: CGFloat
        var directPlacement: Bool = false
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
