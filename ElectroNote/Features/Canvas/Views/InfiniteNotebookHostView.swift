import SwiftUI
import PencilKit

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
            .sheet(isPresented: $vm.showWhiteboard) {
                WhiteboardView { image in
                    vm.pendingImage = image
                }
            }
            .sheet(isPresented: $vm.showPAP) {
                PAPDesignerView { image in
                    vm.pendingImage = image
                }
            }
            .sheet(isPresented: $vm.showMindMap) {
                MindMapDesignerView { image in
                    vm.pendingImage = image
                }
            }
            .sheet(isPresented: $vm.showTextInsertion) {
                TextInsertionSheet(isPresented: $vm.showTextInsertion) { text, fontSize in
                    vm.pendingTextInsertion = .init(text: text, fontSize: fontSize)
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {

        // Left: undo / redo — routed via ViewModel → Representable → VC so the
        // PKCanvasView's undoManager is always the target regardless of first-responder state
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { vm.triggerUndo = true } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("Rückgängig")

            Button { vm.triggerRedo = true } label: { Image(systemName: "arrow.uturn.forward") }
                .accessibilityLabel("Wiederholen")
        }

        // Right: always-visible core controls
        ToolbarItemGroup(placement: .navigationBarTrailing) {

            // Save indicator
            Label(vm.saveState.label, systemImage: vm.saveState.symbol)
                .font(.caption)
                .foregroundStyle(vm.saveState == .unsaved ? .orange : .secondary)
                .labelStyle(.iconOnly)

            // Background template + line spacing
            Menu {
                Section("Vorlage") {
                    ForEach(BackgroundStyle.allCases) { style in
                        Button { vm.background = style } label: {
                            Label(style.rawValue, systemImage: style.symbolName)
                        }
                        .disabled(vm.background == style)
                    }
                }
                Section("Zeilenabstand") {
                    ForEach(LineSpacing.allCases) { sp in
                        Button { vm.lineSpacing = sp } label: {
                            Label(sp.rawValue,
                                  systemImage: vm.lineSpacing == sp ? "checkmark" : "minus")
                        }
                        .disabled(vm.lineSpacing == sp)
                    }
                }
            } label: {
                Image(systemName: vm.background.symbolName)
            }
            .accessibilityLabel("Vorlage & Zeilenabstand")

            // Pencil-only toggle
            Toggle(isOn: $vm.pencilOnly) {
                Image(systemName: vm.pencilOnly ? "pencil.and.scribble" : "hand.draw")
            }
            .toggleStyle(.button)
            .tint(.blue)
            .accessibilityLabel(vm.pencilOnly ? "Nur Pencil" : "Finger & Pencil")

            // Keyboard text insertion
            Button { vm.triggerNativeTextInput = true } label: {
                Image(systemName: "keyboard")
            }
            .accessibilityLabel("Text per Tastatur eingeben")

            // "Mehr" menu — consolidates less-used actions to keep toolbar compact in portrait
            Menu {
                Section("Ansicht") {
                    Toggle(isOn: $vm.rulerActive) {
                        Label("Lineal", systemImage: "ruler")
                    }
                    .tint(.brown)

                    Toggle(isOn: $vm.shapeSnapEnabled) {
                        Label(
                            vm.shapeSnapEnabled ? "Formkorrektur aktiv" : "Formkorrektur",
                            systemImage: vm.shapeSnapEnabled ? "skew" : "scribble"
                        )
                    }
                    .tint(.orange)

                    Toggle(isOn: $vm.darkDrawingMode) {
                        Label(
                            vm.darkDrawingMode ? "Hellmodus" : "Dunkelmodus",
                            systemImage: vm.darkDrawingMode ? "moon.fill" : "moon"
                        )
                    }
                    .tint(.indigo)

                    Toggle(isOn: $vm.mathEnabled) {
                        Label("Mathe-Erkennung", systemImage: "function")
                    }
                    .tint(.purple)
                }

                Section("Einfügen") {
                    Button { vm.triggerAddStickyNote = true } label: {
                        Label("Haftzettel", systemImage: "note.text.badge.plus")
                    }
                    Button { vm.triggerHandwritingRecognition = true } label: {
                        Label("Handschrift erkennen", systemImage: "text.viewfinder")
                    }
                    Button { vm.showPDFPicker = true } label: {
                        Label("PDF einfügen", systemImage: "doc.badge.plus")
                    }
                    Button { vm.showPlotter = true } label: {
                        Label("Funktion einfügen", systemImage: "waveform.path.badge.plus")
                    }

                    // Diagrams submenu
                    Menu {
                        Button { vm.showPAP       = true } label: {
                            Label("Programmablaufplan", systemImage: "arrow.triangle.branch")
                        }
                        Button { vm.showMindMap   = true } label: {
                            Label("MindMap", systemImage: "brain")
                        }
                        Button { vm.showWhiteboard = true } label: {
                            Label("Whiteboard", systemImage: "rectangle.and.pencil.and.ellipsis")
                        }
                    } label: {
                        Label("Diagramm einfügen", systemImage: "plus.rectangle.on.rectangle")
                    }
                }

                Section("Lesezeichen") {
                    Button { vm.triggerAddBookmark   = true } label: {
                        Label("Lesezeichen setzen", systemImage: "bookmark.badge.plus")
                    }
                    Button { vm.triggerShowBookmarks = true } label: {
                        Label("Lesezeichen anzeigen", systemImage: "list.bullet")
                    }
                }

                Section("Stift-Presets") {
                    ForEach(InkPresetStore.shared.presets) { preset in
                        Button { vm.pendingInkPreset = preset } label: {
                            Label(preset.name, systemImage: "paintbrush.pointed")
                        }
                    }
                }

                Section {
                    Button { vm.triggerExport = true } label: {
                        Label("PDF exportieren", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Mehr")
        }
    }
}
