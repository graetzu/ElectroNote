import SwiftUI
import UIKit

struct InfiniteNotebookRepresentable: UIViewControllerRepresentable {

    let store: NotebookDocumentStore
    @ObservedObject var vm: InfiniteNotebookViewModel

    func makeUIViewController(context: Context) -> InfiniteNotebookViewController {
        let vc   = InfiniteNotebookViewController()
        vc.store = store
        vc.onDrawingChanged = { [weak vm] in
            Task { @MainActor in vm?.markUnsaved() }
        }
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

        if let url = vm.pendingPDFURL   { vm.pendingPDFURL = nil; vc.insertPDF(from: url) }
        if let img = vm.pendingImage    { vm.pendingImage  = nil; vc.insertImage(img) }

        if vm.triggerHandwritingRecognition { vm.triggerHandwritingRecognition = false; vc.recogniseHandwriting() }
        if vm.triggerAddStickyNote          { vm.triggerAddStickyNote = false;          vc.addStickyNote() }
        if vm.triggerAddBookmark            { vm.triggerAddBookmark   = false;          vc.addBookmark() }
        if vm.triggerShowBookmarks          { vm.triggerShowBookmarks = false;          vc.showBookmarkList() }

        if let preset = vm.pendingInkPreset {
            vm.pendingInkPreset = nil
            vc.canvasView.tool = preset.pkTool
        }
        if let insertion = vm.pendingTextInsertion {
            vm.pendingTextInsertion = nil
            vc.startTextPlacement(text: insertion.text, fontSize: insertion.fontSize)
        }

        // Undo / Redo — routed through VC so PKCanvasView's undoManager is always the target
        if vm.triggerUndo { vm.triggerUndo = false; vc.canvasView.undoManager?.undo() }
        if vm.triggerRedo { vm.triggerRedo = false; vc.canvasView.undoManager?.redo() }

        // Native text input
        if vm.triggerNativeTextInput { vm.triggerNativeTextInput = false; vc.beginNativeTextInput() }

        // PDF Export
        if vm.triggerExport {
            vm.triggerExport = false
            vc.presentExport()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    final class Coordinator {
        let vm: InfiniteNotebookViewModel
        weak var vc: InfiniteNotebookViewController?
        init(vm: InfiniteNotebookViewModel) { self.vm = vm }
    }
}
