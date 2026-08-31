import SwiftUI
import PencilKit

struct CanvasHostView: View {
    @StateObject private var viewModel: CanvasViewModel
    @State private var canvasRef: PKCanvasView?

    init(item: DocumentItem) {
        _viewModel = StateObject(wrappedValue: CanvasViewModel(item: item))
    }

    var body: some View {
        CanvasRepresentable(
            drawing: Binding(
                get: { viewModel.drawing },
                set: { _ in }           // writes come via onDrawingChanged
            ),
            pencilOnly: $viewModel.pencilOnly,
            onDrawingChanged: { viewModel.drawingDidChange($0) },
            onCanvasReady:    { canvasRef = $0 }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onDisappear { viewModel.save() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Undo / Redo
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button {
                canvasRef?.undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(canvasRef?.undoManager?.canUndo == false)

            Button {
                canvasRef?.undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(canvasRef?.undoManager?.canRedo == false)
        }

        // Save state + Pencil toggle
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            saveIndicator

            Toggle(isOn: $viewModel.pencilOnly) {
                Image(systemName: "pencil.tip")
            }
            .toggleStyle(.button)
            .tint(.blue)
            .help(viewModel.pencilOnly ? "Nur Apple Pencil – Finger scrollt" : "Finger zeichnet auch")
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch viewModel.saveState {
        case .saved:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .pending:
            Button("Speichern") { viewModel.save() }
                .font(.subheadline)
        }
    }
}
