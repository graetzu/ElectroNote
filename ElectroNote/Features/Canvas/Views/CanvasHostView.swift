import SwiftUI
import PencilKit

struct CanvasHostView: View {
    @StateObject private var viewModel: CanvasViewModel
    @StateObject private var clipArtVM: ClipArtViewModel
    @State private var canvasRef: PKCanvasView?
    @State private var showClipArtPicker = false

    init(item: DocumentItem) {
        let vm = CanvasViewModel(item: item)
        _viewModel = StateObject(wrappedValue: vm)
        _clipArtVM = StateObject(wrappedValue: ClipArtViewModel(containerURL: item.path))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CanvasRepresentable(
                    drawing: Binding(get: { viewModel.drawing }, set: { _ in }),
                    pencilOnly: $viewModel.pencilOnly,
                    onDrawingChanged: { viewModel.drawingDidChange($0) },
                    onCanvasReady:    { canvasRef = $0 }
                )

                ClipArtOverlayView(viewModel: clipArtVM)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onDisappear {
            viewModel.save()
            clipArtVM.saveNow()
        }
        .sheet(isPresented: $showClipArtPicker) {
            ClipArtPickerView { entry in
                // Insert at centre of visible canvas
                clipArtVM.insert(entry, at: CGPoint(x: 400, y: 300))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { canvasRef?.undoManager?.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(canvasRef?.undoManager?.canUndo == false)

            Button { canvasRef?.undoManager?.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(canvasRef?.undoManager?.canRedo == false)
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            saveIndicator

            Button { showClipArtPicker = true } label: {
                Image(systemName: "square.on.square.badge.person.crop")
            }
            .help("Symbol einfügen")

            Toggle(isOn: $viewModel.pencilOnly) {
                Image(systemName: "pencil.tip")
            }
            .toggleStyle(.button)
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch viewModel.saveState {
        case .saved:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .pending:
            Button("Speichern") { viewModel.save() }.font(.subheadline)
        }
    }
}
