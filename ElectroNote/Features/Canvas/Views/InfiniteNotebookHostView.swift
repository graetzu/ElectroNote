import SwiftUI
import PencilKit
import PhotosUI

struct InfiniteNotebookHostView: View {
    let item: DocumentItem

    @StateObject private var vm = InfiniteNotebookViewModel()
    @StateObject private var syncVM = SyncViewModel()
    @State private var showNextcloudSheet = false
    @State private var showClipArtPicker  = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    private let store: NotebookDocumentStore

    init(item: DocumentItem) {
        self.item  = item
        self.store = NotebookDocumentStore(noteURL: item.path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            InfiniteNotebookRepresentable(store: store, vm: vm)
                .ignoresSafeArea()

            // Second Top Bar: Pen, Marker, Pencil, Eraser, Lasso, Colors & Widths
            PenToolbarView(vm: vm)
                .padding(.top, 8)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $vm.showPDFPicker) {
            DocumentPicker(contentTypes: DocumentConverter.supportedTypes) { url in
                vm.pendingPDFURL = url
            }
        }
        .sheet(isPresented: $showNextcloudSheet) {
            if syncVM.credentials != nil {
                NavigationStack {
                    NextcloudFileBrowserView(vm: syncVM) { url in
                        showNextcloudSheet = false
                        vm.pendingPDFURL = url
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showNextcloudSheet = false }
                        }
                    }
                }
            } else {
                SyncSettingsView { url in
                    showNextcloudSheet = false
                    vm.pendingPDFURL = url
                }
            }
        }
        .sheet(isPresented: $showClipArtPicker) {
            ClipArtPickerView { entry in
                let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
                if let img = UIImage(systemName: entry.id, withConfiguration: config) {
                    vm.pendingImage = img
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        vm.pendingImage = img
                        selectedPhotoItem = nil
                    }
                }
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
                    Button { vm.triggerPaste = true } label: {
                        Label("Aus Zwischenablage einfügen (Bild/Text)", systemImage: "doc.on.clipboard")
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Bild / Foto einfügen (Mediathek)", systemImage: "photo.badge.plus")
                    }
                    Button { showClipArtPicker = true } label: {
                        Label("Symbol / ClipArt einfügen", systemImage: "star.square")
                    }
                    Button { vm.showTextInsertion = true } label: {
                        Label("Text einfügen", systemImage: "text.cursor")
                    }
                    Button { vm.triggerAddStickyNote = true } label: {
                        Label("Haftzettel", systemImage: "note.text.badge.plus")
                    }
                    Button { vm.triggerHandwritingRecognition = true } label: {
                        Label("Handschrift erkennen", systemImage: "text.viewfinder")
                    }
                    Button { vm.triggerMathRecognition = true } label: {
                        Label("Mathe / Formel berechnen", systemImage: "function")
                    }
                    Button { vm.showPDFPicker = true } label: {
                        Label("Dokument einfügen (PDF, Word, Excel, PPT…)", systemImage: "doc.badge.plus")
                    }
                    Button { showNextcloudSheet = true } label: {
                        Label("Aus Nextcloud einfügen…", systemImage: "icloud.and.arrow.down")
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

// MARK: - Dedicated Pen & Tool Top Bar

struct PenToolbarView: View {
    @Binding var activeTool: CanvasToolType
    @Binding var selectedColor: Color
    @Binding var selectedWidth: CGFloat
    @Binding var eraserType: PKEraserTool.EraserType
    @Binding var rulerActive: Bool
    var darkDrawingMode: Bool = false
    var showRuler: Bool = true
    var onToolChanged: ((PKTool) -> Void)? = nil

    private let quickColors: [Color] = [
        .black,
        .blue,
        .red,
        .green,
        .yellow,
        .orange,
        .purple
    ]

    private let strokeWidths: [(label: String, width: CGFloat, dotSize: CGFloat)] = [
        ("Fein", 1.5, 4),
        ("Normal", 3.0, 7),
        ("Mittel", 5.5, 11),
        ("Dick", 9.0, 16)
    ]

    init(activeTool: Binding<CanvasToolType>,
         selectedColor: Binding<Color>,
         selectedWidth: Binding<CGFloat>,
         eraserType: Binding<PKEraserTool.EraserType>,
         rulerActive: Binding<Bool> = .constant(false),
         darkDrawingMode: Bool = false,
         showRuler: Bool = true,
         onToolChanged: ((PKTool) -> Void)? = nil) {
        self._activeTool = activeTool
        self._selectedColor = selectedColor
        self._selectedWidth = selectedWidth
        self._eraserType = eraserType
        self._rulerActive = rulerActive
        self.darkDrawingMode = darkDrawingMode
        self.showRuler = showRuler
        self.onToolChanged = onToolChanged
    }

    var onPaste: (() -> Void)? = nil
    var onTextRecognition: (() -> Void)? = nil
    var onMathRecognition: (() -> Void)? = nil

    init(vm: InfiniteNotebookViewModel) {
        self._activeTool = Binding(get: { vm.activeTool }, set: { vm.activeTool = $0 })
        self._selectedColor = Binding(get: { vm.selectedColor }, set: { vm.selectedColor = $0 })
        self._selectedWidth = Binding(get: { vm.selectedWidth }, set: { vm.selectedWidth = $0 })
        self._eraserType = Binding(get: { vm.eraserType }, set: { vm.eraserType = $0 })
        self._rulerActive = Binding(get: { vm.rulerActive }, set: { vm.rulerActive = $0 })
        self.darkDrawingMode = vm.darkDrawingMode
        self.showRuler = true
        self.onToolChanged = nil
        self.onPaste = { [weak vm] in vm?.triggerPaste = true }
        self.onTextRecognition = { [weak vm] in vm?.triggerHandwritingRecognition = true }
        self.onMathRecognition = { [weak vm] in vm?.triggerMathRecognition = true }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tool selector
            HStack(spacing: 4) {
                ForEach(CanvasToolType.allCases) { tool in
                    Button {
                        if activeTool == tool && tool == .eraser {
                            eraserType = eraserType == .vector ? .bitmap : .vector
                        } else {
                            activeTool = tool
                        }
                        notifyToolChange()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 32)
                                .background(
                                    activeTool == tool ?
                                    Color.accentColor.opacity(0.18) : Color.clear
                                )
                                .foregroundColor(
                                    activeTool == tool ?
                                    Color.accentColor : Color.primary.opacity(0.75)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            if activeTool == tool && tool == .eraser {
                                Text(eraserType == .vector ? "Strich" : "Pixel")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(tool.rawValue)
                }
            }

            if activeTool == .lasso {
                Divider()
                    .frame(height: 22)

                HStack(spacing: 6) {
                    Button {
                        onPaste?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Einfügen")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                    }

                    Button {
                        onTextRecognition?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Text")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }

                    Button {
                        onMathRecognition?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "function")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Mathe")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                    }
                }
            }

            if activeTool != .eraser && activeTool != .lasso {
                Divider()
                    .frame(height: 22)

                // Quick Color palette
                HStack(spacing: 6) {
                    ForEach(quickColors, id: \.self) { color in
                        let displayColor = (color == .black && darkDrawingMode) ? Color.white : color
                        Button {
                            selectedColor = color
                            notifyToolChange()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(displayColor)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                                    )

                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(displayColor == .white || displayColor == .yellow ? .black : .white)
                                }
                            }
                        }
                        .accessibilityLabel("Farbe")
                    }

                    // Native ColorPicker for unlimited color options
                    ColorPicker("", selection: Binding(get: { selectedColor }, set: { selectedColor = $0; notifyToolChange() }))
                        .labelsHidden()
                        .scaleEffect(0.85)
                }

                Divider()
                    .frame(height: 22)

                // Stroke width buttons
                HStack(spacing: 8) {
                    ForEach(strokeWidths, id: \.width) { item in
                        Button {
                            selectedWidth = item.width
                            notifyToolChange()
                        } label: {
                            Circle()
                                .fill(selectedWidth == item.width ? Color.accentColor : Color.primary.opacity(0.4))
                                .frame(width: item.dotSize, height: item.dotSize)
                                .frame(width: 26, height: 26)
                                .background(
                                    selectedWidth == item.width ?
                                    Color.accentColor.opacity(0.15) : Color.clear
                                )
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(item.label)
                    }
                }
            }

            if showRuler {
                Divider()
                    .frame(height: 22)

                // Lineal (Ruler) Toggle
                Button {
                    rulerActive.toggle()
                } label: {
                    Image(systemName: "ruler")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(rulerActive ? Color.brown.opacity(0.2) : Color.clear)
                        .foregroundColor(rulerActive ? Color.brown : Color.primary.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Lineal")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private func notifyToolChange() {
        let tool = makePKTool(tool: activeTool, color: selectedColor, width: selectedWidth, eraserType: eraserType, darkDrawingMode: darkDrawingMode)
        onToolChanged?(tool)
    }
}
