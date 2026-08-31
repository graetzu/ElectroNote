import SwiftUI
import UIKit

struct InfiniteNotebookRepresentable: UIViewControllerRepresentable {

    let store: NotebookDocumentStore
    @ObservedObject var vm: InfiniteNotebookViewModel

    func makeUIViewController(context: Context) -> InfiniteNotebookViewController {
        let vc    = InfiniteNotebookViewController()
        vc.store  = store
        vc.onDrawingChanged = { [weak vm] in
            Task { @MainActor in vm?.markUnsaved() }
        }
        context.coordinator.vc = vc
        return vc
    }

    func updateUIViewController(_ vc: InfiniteNotebookViewController, context: Context) {
        vc.pencilOnly   = vm.pencilOnly
        vc.mathEnabled  = vm.mathEnabled

        if vc.background != vm.background {
            vc.background = vm.background
        }

        if let url = vm.pendingPDFURL {
            vm.pendingPDFURL = nil
            vc.insertPDF(from: url)
        }

        if let image = vm.pendingImage {
            vm.pendingImage = nil
            vc.insertImage(image)
        }

        if vm.triggerHandwritingRecognition {
            vm.triggerHandwritingRecognition = false
            vc.recogniseHandwriting()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    // MARK: - Coordinator

    final class Coordinator {
        let vm: InfiniteNotebookViewModel
        weak var vc: InfiniteNotebookViewController?

        init(vm: InfiniteNotebookViewModel) { self.vm = vm }
    }
}
