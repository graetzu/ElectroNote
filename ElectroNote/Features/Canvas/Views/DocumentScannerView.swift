import SwiftUI
import UIKit
import VisionKit

// MARK: - DocumentScannerView

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if VNDocumentCameraViewController.isSupported {
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = context.coordinator
            return scanner
        } else {
            // Fallback for unsupported devices
            let alertVC = UIAlertController(
                title: "Scanner nicht unterstützt",
                message: "Der Dokumentenscanner wird auf diesem Gerät nicht unterstützt.",
                preferredStyle: .alert
            )
            alertVC.addAction(UIAlertAction(title: "OK", style: .default) { [weak alertVC] _ in
                alertVC?.dismiss(animated: true) {
                    dismiss()
                }
            })
            return alertVC
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.parent.onScan(images)
                self.parent.dismiss()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { [weak self] in
                self?.parent.dismiss()
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true) { [weak self] in
                self?.parent.dismiss()
            }
        }
    }
}
