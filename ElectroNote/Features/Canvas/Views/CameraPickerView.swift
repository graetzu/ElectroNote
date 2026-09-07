import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - CameraPickerView

struct CameraPickerView: UIViewControllerRepresentable {
    enum CaptureMode {
        case photo
        case video
    }

    let mode: CaptureMode
    let onPhotoCaptured: ((UIImage) -> Void)?
    let onVideoCaptured: ((URL) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(mode: CaptureMode,
         onPhotoCaptured: ((UIImage) -> Void)? = nil,
         onVideoCaptured: ((URL) -> Void)? = nil) {
        self.mode = mode
        self.onPhotoCaptured = onPhotoCaptured
        self.onVideoCaptured = onVideoCaptured
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            switch mode {
            case .photo:
                picker.mediaTypes = [UTType.image.identifier]
                picker.cameraCaptureMode = .photo
            case .video:
                picker.mediaTypes = [UTType.movie.identifier]
                picker.cameraCaptureMode = .video
                picker.videoQuality = .typeHigh
            }
        } else {
            // Fallback for Simulator without camera
            picker.sourceType = .photoLibrary
            picker.mediaTypes = (mode == .photo) ? [UTType.image.identifier] : [UTType.movie.identifier]
        }

        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if let image = info[.originalImage] as? UIImage {
                    self.parent.onPhotoCaptured?(image)
                } else if let videoURL = info[.mediaURL] as? URL {
                    self.parent.onVideoCaptured?(videoURL)
                }
                self.parent.dismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.parent.dismiss()
            }
        }
    }
}
