import SwiftUI

struct InfiniteNotebookHostView: View {
    let item: DocumentItem

    @StateObject private var vm = InfiniteNotebookViewModel()
    private let store: NotebookDocumentStore

    init(item: DocumentItem) {
        self.item  = item
        self.store = NotebookDocumentStore(noteURL: item.path)
    }

    var body: some View {
        InfiniteNotebookRepresentable(store: store, vm: vm)
            .ignoresSafeArea()
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .sheet(isPresented: $vm.showPDFPicker) {
                DocumentPicker(contentTypes: [.pdf]) { url in
                    vm.pendingPDFURL = url
                }
            }
            .sheet(isPresented: $vm.showPlotter) {
                PlotInserterView { image in
                    vm.pendingImage = image
                }
                .presentationDetents([.medium, .large])
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {

        // Left: undo / redo (use system UndoManager via first responder)
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { UIApplication.shared.sendAction(#selector(UndoManager.undo), to: nil, from: nil, for: nil) }
            label: { Image(systemName: "arrow.uturn.backward") }
            .accessibilityLabel("Rückgängig")

            Button { UIApplication.shared.sendAction(#selector(UndoManager.redo), to: nil, from: nil, for: nil) }
            label: { Image(systemName: "arrow.uturn.forward") }
            .accessibilityLabel("Wiederholen")
        }

        // Right: feature buttons + save indicator
        ToolbarItemGroup(placement: .navigationBarTrailing) {

            // Save state
            Label(vm.saveState.label, systemImage: vm.saveState.symbol)
                .font(.caption)
                .foregroundStyle(vm.saveState == .unsaved ? .orange : .secondary)
                .labelStyle(.iconOnly)

            // Background picker
            Menu {
                ForEach(BackgroundStyle.allCases) { style in
                    Button {
                        vm.background = style
                    } label: {
                        Label(style.rawValue, systemImage: style.symbolName)
                    }
                    .disabled(vm.background == style)
                }
            } label: {
                Image(systemName: vm.background.symbolName)
            }
            .accessibilityLabel("Hintergrund")

            // Pencil-only toggle
            Toggle(isOn: $vm.pencilOnly) {
                Image(systemName: vm.pencilOnly ? "pencil.and.scribble" : "hand.draw")
            }
            .toggleStyle(.button)
            .tint(.blue)
            .accessibilityLabel(vm.pencilOnly ? "Nur Pencil" : "Finger & Pencil")

            // Math mode toggle
            Toggle(isOn: $vm.mathEnabled) {
                Image(systemName: "function")
            }
            .toggleStyle(.button)
            .tint(.purple)
            .accessibilityLabel("Mathe-Erkennung")

            // Handwriting recognition (manual)
            Button {
                // The Coordinator holds a weak ref to the VC; call through binding
                vm.triggerHandwritingRecognition = true
            } label: {
                Image(systemName: "text.viewfinder")
            }
            .accessibilityLabel("Handschrift erkennen")

            // Insert PDF
            Button { vm.showPDFPicker = true } label: {
                Image(systemName: "doc.badge.plus")
            }
            .accessibilityLabel("PDF einfügen")

            // Insert function plot
            Button { vm.showPlotter = true } label: {
                Image(systemName: "waveform.path.badge.plus")
            }
            .accessibilityLabel("Funktion einfügen")
        }
    }
}
