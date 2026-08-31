import SwiftUI
import PDFKit

struct PDFRepresentable: UIViewControllerRepresentable {
    @ObservedObject var viewModel: PDFViewModel

    func makeUIViewController(context: Context) -> PDFAnnotationViewController {
        let vc = PDFAnnotationViewController()
        guard let document = viewModel.document,
              let store    = viewModel.annotationStore else { return vc }

        vc.configure(document: document, store: store, pageIndex: viewModel.currentPageIndex)

        vc.onPageChanged = { [coordinator = context.coordinator] index in
            coordinator.lastKnownPageIndex = index
            Task { @MainActor in
                viewModel.currentPageIndex = index
            }
        }
        vc.onAnnotationChanged = {
            Task { @MainActor in
                viewModel.hasUnsavedAnnotations = true
            }
        }

        context.coordinator.lastKnownPageIndex = viewModel.currentPageIndex
        return vc
    }

    func updateUIViewController(_ vc: PDFAnnotationViewController, context: Context) {
        // Programmatic navigation (toolbar prev/next)
        let desired = viewModel.currentPageIndex
        guard context.coordinator.lastKnownPageIndex != desired else { return }
        context.coordinator.lastKnownPageIndex = desired
        vc.navigateTo(pageIndex: desired)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastKnownPageIndex: Int = 0
    }
}
