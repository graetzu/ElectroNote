import SwiftUI
import UIKit
import PencilKit

struct InfiniteNotebookRepresentable: UIViewControllerRepresentable {

    let store: NotebookDocumentStore
    @ObservedObject var vm: InfiniteNotebookViewModel

    func makeUIViewController(context: Context) -> InfiniteNotebookViewController {
        let vc   = InfiniteNotebookViewController()
        vc.store = store
        let toolColor = vm.darkDrawingMode ? UIColor.white : UIColor(vm.selectedColor)
        vc.canvasView.tool = PKInkingTool(.pen, color: toolColor, width: vm.selectedWidth)
        vc.onDrawingChanged = { [weak vm] in
            Task { @MainActor in vm?.markUnsaved() }
        }
        vc.onToolChanged = { [weak vm] newTool in
            Task { @MainActor in vm?.activeTool = newTool }
        }
        vc.onPlayMedia = { [weak vm] item in
            Task { @MainActor in vm?.activePlaybackMedia = item }
        }
        vm.attach(vc: vc)
        context.coordinator.vc = vc
        return vc
    }

    func updateUIViewController(_ vc: InfiniteNotebookViewController, context: Context) {
        vc.pencilOnly  = vm.pencilOnly
        vc.mathEnabled = vm.mathEnabled

        if vc.background != vm.background               { vc.background        = vm.background        }
        if vc.lineSpacing != vm.lineSpacing               { vc.lineSpacing       = vm.lineSpacing        }
        if vc.darkDrawingMode != vm.darkDrawingMode       { vc.darkDrawingMode   = vm.darkDrawingMode    }
        if vc.shapeSnapEnabled != vm.shapeSnapEnabled     { vc.shapeSnapEnabled  = vm.shapeSnapEnabled   }

        // Ruler
        if vc.canvasView.isRulerActive != vm.rulerActive {
            vc.canvasView.isRulerActive = vm.rulerActive
        }

        if let url = vm.pendingPDFURL   { vm.pendingPDFURL = nil; vc.insertFile(from: url) }
        if let img = vm.pendingImage    { vm.pendingImage  = nil; vc.insertImage(img) }
        if let media = vm.pendingMediaInsertion { vm.pendingMediaInsertion = nil; vc.insertMedia(media) }

        if vm.triggerHandwritingRecognition { vm.triggerHandwritingRecognition = false; vc.recogniseHandwriting() }
        if vm.triggerMathRecognition        { vm.triggerMathRecognition = false;        vc.recogniseMathSelection() }
        if vm.triggerPaste                  { vm.triggerPaste = false;                  vc.pasteFromClipboard() }
        if vm.triggerAddStickyNote          { vm.triggerAddStickyNote = false;          vc.addStickyNote() }
        if let text = vm.pendingStickyNoteText { vm.pendingStickyNoteText = nil; vc.addStickyNote(text: text) }
        if vm.triggerAddBookmark            { vm.triggerAddBookmark   = false;          vc.addBookmark() }
        if vm.triggerShowBookmarks          { vm.triggerShowBookmarks = false;          vc.showBookmarkList() }

        if vc.currentCanvasToolType != vm.activeTool {
            vc.setCanvasToolType(vm.activeTool)
        }
        if let preset = vm.pendingInkPreset {
            vm.pendingInkPreset = nil
            if vm.activeTool != .pan && vm.activeTool != .lasso && vm.activeTool != .textSelect {
                vc.canvasView.tool = preset.pkTool
            }
        }
        if let tool = vm.pendingPKTool {
            vm.pendingPKTool = nil
            if vm.activeTool != .pan && vm.activeTool != .lasso && vm.activeTool != .textSelect {
                vc.canvasView.tool = tool
            }
        }
        if let insertion = vm.pendingTextInsertion {
            vm.pendingTextInsertion = nil
            vc.startTextPlacement(text: insertion.text, fontSize: insertion.fontSize)
        }

        // Undo / Redo — routed through VC so unified undoAction/redoAction handles strokes and elements
        if vm.triggerUndo { vm.triggerUndo = false; vc.undoAction() }
        if vm.triggerRedo { vm.triggerRedo = false; vc.redoAction() }

        // Native text input
        if vm.triggerNativeTextInput { vm.triggerNativeTextInput = false; vc.beginNativeTextInput() }

        // PDF Export
        if vm.triggerExport {
            vm.triggerExport = false
            vc.presentExport()
        }

        // In-Canvas Find & Search
        if vm.showSearch {
            if !context.coordinator.isSearchActive || context.coordinator.lastSearchQuery != vm.searchQuery {
                context.coordinator.isSearchActive = true
                context.coordinator.lastSearchQuery = vm.searchQuery
                vc.performSearch(query: vm.searchQuery) { count in
                    Task { @MainActor in
                        vm.searchMatchCount = count
                        vm.currentSearchMatchIndex = count > 0 ? 0 : 0
                    }
                }
            }
            if vm.triggerNextSearchMatch {
                vm.triggerNextSearchMatch = false
                let newIdx = vc.navigateSearchMatch(forward: true)
                vm.currentSearchMatchIndex = newIdx
            }
            if vm.triggerPreviousSearchMatch {
                vm.triggerPreviousSearchMatch = false
                let newIdx = vc.navigateSearchMatch(forward: false)
                vm.currentSearchMatchIndex = newIdx
            }
        } else if context.coordinator.isSearchActive {
            context.coordinator.isSearchActive = false
            context.coordinator.lastSearchQuery = ""
            vc.clearSearchHighlights()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    final class Coordinator {
        let vm: InfiniteNotebookViewModel
        weak var vc: InfiniteNotebookViewController?
        var lastSearchQuery: String = ""
        var isSearchActive: Bool = false
        init(vm: InfiniteNotebookViewModel) { self.vm = vm }
    }
}
