import SwiftUI
import PencilKit
import PhotosUI
import AVFoundation

struct InfiniteNotebookHostView: View {
    let item: DocumentItem
    var isWhiteboardMode: Bool = false
    var onInsert: ((UIImage) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: InfiniteNotebookViewModel
    @StateObject private var syncVM = SyncViewModel()
    @ObservedObject private var syncManager = UnifiedSyncManager.shared
    @State private var showNextcloudSheet = false
    @State private var showGoogleDriveSheet = false
    @State private var showSettingsSheet = false
    @State private var showClipArtPicker  = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    private let store: NotebookDocumentStore

    init(item: DocumentItem, isWhiteboardMode: Bool = false, onInsert: ((UIImage) -> Void)? = nil) {
        self.item  = item
        self.isWhiteboardMode = isWhiteboardMode
        self.onInsert = onInsert
        let st = NotebookDocumentStore(noteURL: item.path)
        self.store = st
        let doc = st.loadDocument()
        let vm = InfiniteNotebookViewModel()
        vm.background = doc.background
        vm.lineSpacing = doc.lineSpacing
        vm.mathEnabled = doc.mathEnabled
        vm.darkDrawingMode = doc.darkDrawingMode
        vm.shapeSnapEnabled = doc.shapeSnapEnabled
        #if targetEnvironment(macCatalyst)
        vm.pencilOnly = false
        vm.activeTool = .textSelect
        #endif
        self._vm = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dedicated Pen, Tool, Shape, OCR & Math Top Bar
            PenToolbarView(
                vm: vm,
                onNextcloud: { showNextcloudSheet = true },
                onGoogleDrive: {
                    if syncManager.googleDriveEngine.isConnected {
                        showGoogleDriveSheet = true
                    } else {
                        showSettingsSheet = true
                    }
                },
                onCloudSettings: { showSettingsSheet = true }
            )
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))

            Divider()

            ZStack(alignment: .topTrailing) {
                InfiniteNotebookRepresentable(store: store, vm: vm, isWhiteboardMode: isWhiteboardMode)
                    .ignoresSafeArea(edges: .bottom)

                if vm.showSearch {
                    CanvasFindBarView(
                        query: $vm.searchQuery,
                        matchCount: vm.searchMatchCount,
                        currentIndex: vm.currentSearchMatchIndex,
                        onPrevious: { vm.triggerPreviousSearchMatch = true },
                        onNext: { vm.triggerNextSearchMatch = true },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.showSearch = false
                            }
                        }
                    )
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
                }

                if vm.showAISidebar {
                    AISidebarView(
                        vm: vm,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                vm.showAISidebar = false
                            }
                        }
                    )
                    .transition(.move(edge: .trailing))
                    .zIndex(30)
                }

                if vm.isRangeExportModeActive {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("PDF-BEREICH")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text("S. \(vm.exportRangeStartPage) bis \(vm.exportRangeEndPage)")
                                    .font(.subheadline.weight(.bold))
                            }
                            .padding(.trailing, 2)

                            Divider()
                                .frame(height: 24)

                            Button {
                                vm.setRangeStartAtCurrentScroll()
                            } label: {
                                Label("Start", systemImage: "arrow.down.to.line")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                vm.setRangeEndAtCurrentScroll()
                            } label: {
                                Label("Ende", systemImage: "arrow.up.to.line")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                vm.snapRangeToPages()
                            } label: {
                                Label("Ganze Seite", systemImage: "arrow.up.and.down.and.sparkles")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                vm.executeRangeExport()
                            } label: {
                                Label("Exportieren", systemImage: "square.and.arrow.up.fill")
                                    .font(.subheadline.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                vm.cancelRangeExportMode()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(40)
                }

                if vm.showScientificCalculator {
                    ScientificCalculatorFloatingView(
                        store: .shared,
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                vm.showScientificCalculator = false
                            }
                        },
                        onInsertIntoNote: { text in
                            vm.pendingTextInsertion = InfiniteNotebookViewModel.TypedTextInsertion(text: text, fontSize: 20, directPlacement: true)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                ScientificCalculatorStore.shared.isMinimized = true
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .zIndex(50)
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $vm.showPDFPicker) {
            DocumentPicker(contentTypes: DocumentConverter.supportedTypes + [.image]) { url in
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
        .sheet(isPresented: $showGoogleDriveSheet) {
            if let creds = syncManager.googleDriveEngine.credentials {
                GoogleDriveFileBrowserView(credentials: creds) { url in
                    showGoogleDriveSheet = false
                    vm.pendingPDFURL = url
                }
            } else {
                AppSettingsView { url in
                    showGoogleDriveSheet = false
                    vm.pendingPDFURL = url
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            AppSettingsView { url in
                showSettingsSheet = false
                vm.pendingPDFURL = url
            }
        }
        .sheet(isPresented: $vm.showWebClipper) {
            WebClipperView { action in
                switch action {
                case .insertImage(let img, _):
                    vm.pendingImage = img
                case .insertImageAndStickyNote(let img, let text):
                    vm.pendingImage = img
                    vm.pendingStickyNoteText = text
                case .insertTextOnly(let text):
                    vm.pendingTextInsertion = InfiniteNotebookViewModel.TypedTextInsertion(text: text, fontSize: 16)
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
        .sheet(isPresented: $vm.showCircuitPicker) {
            CircuitSymbolPickerView(isDarkCanvas: vm.darkDrawingMode) { image in
                vm.pendingImage = image
            }
        }
        .sheet(isPresented: $vm.showElektroSim) {
            ElektroSimWebSheetView { image in
                vm.pendingImage = image
            }
        }
        .sheet(isPresented: $vm.showCameraPhoto) {
            CameraPickerView(mode: .photo) { image in
                vm.pendingImage = image
            }
        }
        .sheet(isPresented: $vm.showDocumentScanner) {
            DocumentScannerView { images in
                for image in images {
                    vm.pendingImage = image
                }
            }
        }
        .sheet(isPresented: $vm.showCameraVideo) {
            CameraPickerView(mode: .video) { videoURL in
                handleIncomingVideo(videoURL)
            }
        }
        .sheet(isPresented: $vm.showYouTubeEmbed) {
            YouTubeEmbedSheet { media in
                vm.pendingMediaInsertion = media
            }
        }
        .sheet(item: $vm.activePlaybackMedia) { mediaItem in
            MediaPlaybackSheetView(item: mediaItem, noteURL: item.path)
        }
        .sheet(isPresented: $vm.showPDFExportSheet) {
            NotebookPDFExportSheet(
                documentName: item.name,
                totalPages: vm.exportTotalPages,
                currentPage: vm.exportCurrentPage,
                initialStartPage: vm.exportRangeStartPage,
                initialEndPage: vm.exportRangeEndPage,
                onExport: { scope, cropExact in
                    vm.executePDFExport(scope: scope, cropToExactHeight: cropExact)
                },
                onSelectRangeInNotebook: {
                    vm.startRangeExportMode()
                },
                onCancel: {
                    vm.showPDFExportSheet = false
                }
            )
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let movie = try? await newItem.loadTransferable(type: MovieTransferable.self) {
                    handleIncomingVideo(movie.url)
                    await MainActor.run { selectedVideoItem = nil }
                } else if let data = try? await newItem.loadTransferable(type: Data.self) {
                    if let filename = try? store.saveVideoData(data) {
                        let storedURL = store.videoURL(filename: filename)
                        let thumb = await generateVideoThumbnail(for: storedURL)
                        await MainActor.run {
                            vm.pendingMediaInsertion = MediaInsertion(
                                thumbnail: thumb,
                                mediaType: "video",
                                mediaURLString: filename,
                                title: "Video"
                            )
                            selectedVideoItem = nil
                        }
                    }
                }
            }
        }
        .onDisappear {
            if UnifiedSyncManager.shared.autoSyncOnSave {
                UnifiedSyncManager.shared.syncActiveProvider()
            }
        }
    }

    private func handleIncomingVideo(_ sourceURL: URL) {
        Task {
            do {
                let filename = try store.copyVideo(from: sourceURL)
                let storedURL = store.videoURL(filename: filename)
                let thumb = await generateVideoThumbnail(for: storedURL)
                await MainActor.run {
                    vm.pendingMediaInsertion = MediaInsertion(
                        thumbnail: thumb,
                        mediaType: "video",
                        mediaURLString: filename,
                        title: "Video"
                    )
                }
            } catch {
                print("Error copying video: \(error)")
            }
        }
    }

    private func generateVideoThumbnail(for url: URL) async -> UIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let (cgImage, _) = try? await generator.image(at: time) {
            return UIImage(cgImage: cgImage)
        }
        let size = CGSize(width: 480, height: 320)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            if let icon = UIImage(systemName: "video.fill", withConfiguration: config) {
                icon.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(at: CGPoint(x: (size.width - icon.size.width) / 2, y: (size.height - icon.size.height) / 2))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {

        // Left: undo / redo — routed via ViewModel → Representable → VC so the
        // PKCanvasView's undoManager is always the target regardless of first-responder state
        ToolbarItemGroup(placement: .navigationBarLeading) {
            if onInsert != nil {
                Button("Schließen") { dismiss() }
            }

            Button { vm.triggerUndo = true } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("Rückgängig")

            Button { vm.triggerRedo = true } label: { Image(systemName: "arrow.uturn.forward") }
                .accessibilityLabel("Wiederholen")
        }

        // Right: always-visible core controls
        ToolbarItemGroup(placement: .navigationBarTrailing) {

            if let onInsert {
                Button {
                    if let img = vm.renderCanvasSnapshotImage() {
                        onInsert(img)
                        dismiss()
                    }
                } label: {
                    Label("Einfügen", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
            }

            // Save status indicator with clear description
            Label(vm.saveState.label, systemImage: vm.saveState.symbol)
                .font(.caption)
                .foregroundStyle(vm.saveState == .unsaved ? .orange : .secondary)
                .labelStyle(.iconOnly)
                .help("Automatischer Speicherstatus")

            // Dark Mode / Hellmodus Direktschalter (1 Fingertipp)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.darkDrawingMode.toggle()
                }
            } label: {
                Image(systemName: vm.darkDrawingMode ? "moon.fill" : "moon")
            }
            .tint(vm.darkDrawingMode ? .indigo : .primary)
            .accessibilityLabel(vm.darkDrawingMode ? "Hellmodus aktivieren" : "Dunkelmodus aktivieren")
            .help("Dunkelmodus umschalten")

            // In-Canvas Suche (Handschrift, Text & Notizen)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.showSearch.toggle()
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .tint(vm.showSearch ? .accentColor : .primary)
            .accessibilityLabel(vm.showSearch ? "Suche schließen" : "In Notiz suchen")
            .help("In Notiz und Handschrift suchen")

            // KI-Assistent Seitenleiste (ChatGPT, Claude, Gemini)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    vm.showAISidebar.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: vm.showAISidebar ? "sparkles.rectangle.stack.fill" : "sparkles")
                    if vm.showAISidebar {
                        Text("KI")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
            }
            .tint(vm.showAISidebar ? .purple : .primary)
            .accessibilityLabel(vm.showAISidebar ? "KI-Assistent schließen" : "KI-Assistent öffnen")
            .help("KI-Seitenleiste (ChatGPT, Claude, Gemini)")

            // Background template + line spacing
            // (Dunkelmodus lebt nur noch im direkten Mond-Button oben — nicht hier duplizieren)
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

            // Mode Switch: Schreiben (Stift schreibt, Finger scrollt) vs. Scrollen (Stift & Finger scrollen)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.togglePanMode()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: vm.activeTool == .pan ? "hand.draw.fill" : "pencil.tip")
                        .font(.system(size: 13, weight: .bold))
                    Text(vm.activeTool == .pan ? "Scrollen" : "Schreiben")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(vm.activeTool == .pan ? Color.blue : Color(uiColor: .tertiarySystemFill))
                .foregroundColor(vm.activeTool == .pan ? .white : .primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.activeTool == .pan ? "Scroll-Modus aktiv: Stift & Finger scrollen" : "Schreib-Modus aktiv: Stift schreibt")
            .help(vm.activeTool == .pan ? "Tippen zum Schreiben mit dem Stift" : "Tippen zum Scrollen/Bewegen mit dem Stift")

            // Keyboard text insertion
            Button { vm.triggerNativeTextInput = true } label: {
                Image(systemName: "keyboard")
            }
            .accessibilityLabel("Text per Tastatur eingeben")

            // Live Collaboration (Interaktive Zusammenarbeit)
            LiveCollabBadgeButton(documentName: item.name, documentType: isWhiteboardMode ? .whiteboard : .note)

            // Live Cast Button (WLAN Übertragung)
            LiveCastBadgeButton()

            // Direct Import & Insert Menu (Fotos, Videos, Notizen & Diagramme)
            Menu {
                Section("Dateien & Fotos") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Foto aus Mediathek…", systemImage: "photo.badge.plus")
                    }
                    Button {
                        vm.showCameraPhoto = true
                    } label: {
                        Label("Foto mit Kamera aufnehmen…", systemImage: "camera")
                    }
                    Button {
                        vm.showDocumentScanner = true
                    } label: {
                        Label("Dokument / Tafel scannen…", systemImage: "doc.viewfinder")
                    }
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Label("Video aus Mediathek…", systemImage: "video.badge.plus")
                    }
                    Button {
                        vm.showCameraVideo = true
                    } label: {
                        Label("Video mit Kamera aufnehmen…", systemImage: "video")
                    }
                    Button {
                        vm.showPDFPicker = true
                    } label: {
                        Label("Datei / PDF importieren…", systemImage: "folder.badge.plus")
                    }
                }

                Section("Notiz-Elemente") {
                    Button { vm.triggerNativeTextInput = true } label: {
                        Label("Text einfügen", systemImage: "text.cursor")
                    }
                    Button { vm.triggerAddStickyNote = true } label: {
                        Label("Haftzettel", systemImage: "note.text.badge.plus")
                    }
                    Button { showClipArtPicker = true } label: {
                        Label("Symbol / ClipArt…", systemImage: "star.square")
                    }
                    Button { vm.triggerPaste = true } label: {
                        Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Erkennung & Diagramme") {
                    Button { vm.triggerHandwritingRecognition = true } label: {
                        Label("Handschrift erkennen", systemImage: "text.viewfinder")
                    }
                    Button { vm.showWhiteboard = true } label: {
                        Label("Whiteboard", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    Button { vm.showMindMap   = true } label: {
                        Label("MindMap", systemImage: "brain")
                    }
                    Button { vm.showPAP       = true } label: {
                        Label("Programmablaufplan", systemImage: "arrow.triangle.branch")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Einfügen")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
            .accessibilityLabel("Dateien und Notiz-Inhalte einfügen")

            // "Mehr" menu — Einstellungen, Elektro & Technik, Lesezeichen, Export
            Menu {
                Section("Ansicht & Stift") {
                    Toggle(isOn: $vm.pencilOnly) {
                        Label(
                            vm.pencilOnly ? "Nur Pencil schreibt (1 Finger scrollt)" : "Finger & Pencil zeichnen",
                            systemImage: vm.pencilOnly ? "pencil.and.scribble" : "hand.draw"
                        )
                    }
                    .tint(.blue)

                    Toggle(isOn: $vm.mathEnabled) {
                        Label("Mathe-Erkennung (automatisch)", systemImage: "function")
                    }
                    .tint(.purple)
                }

                Section("Elektro & Technik") {
                    Menu {
                        Button { vm.showCircuitPicker = true } label: {
                            Label("Schaltpläne & Schaltsymbole", systemImage: "bolt.badge.clock")
                        }
                        Button { vm.showElektroSim = true } label: {
                            Label("⚡️ Elektro-Planer (Website)…", systemImage: "bolt.horizontal.circle")
                        }
                        Button { vm.triggerMathRecognition = true } label: {
                            Label("Mathe Handschrifterkennung", systemImage: "function")
                        }
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                vm.toggleScientificCalculator()
                            }
                        } label: {
                            Label("Wissenschaftlicher Taschenrechner", systemImage: "plus.forwardslash.minus")
                        }
                        Button { vm.showPlotter = true } label: {
                            Label("Funktionsplotter…", systemImage: "waveform.path.badge.plus")
                        }
                    } label: {
                        Label("Elektro & Technik…", systemImage: "bolt.badge.clock")
                    }
                }

                Section("Lesezeichen") {
                    Button { vm.triggerAddBookmark   = true } label: {
                        Label("Lesezeichen setzen", systemImage: "bookmark")
                    }
                    Button { vm.triggerShowBookmarks = true } label: {
                        Label("Lesezeichen anzeigen", systemImage: "list.bullet")
                    }
                }

                Section("Export") {
                    Button { vm.openPDFExportDialog() } label: {
                        Label("PDF exportieren…", systemImage: "square.and.arrow.up")
                    }
                    Button { vm.startRangeExportMode() } label: {
                        Label("Bereich als PDF exportieren…", systemImage: "crop")
                    }
                }

                Section("Cloud") {
                    Button { showSettingsSheet = true } label: {
                        Label("Cloud & Synchronisation…", systemImage: "arrow.triangle.2.circlepath.icloud")
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
    @Binding var eraserWidth: CGFloat
    @Binding var rulerActive: Bool
    @Binding var shapeSnapEnabled: Bool
    var darkDrawingMode: Bool = false
    var showRuler: Bool = true
    var onToolChanged: ((PKTool) -> Void)? = nil

    @State private var localEraserWidth: CGFloat = 16.0
    private var usesLocalEraserWidth: Bool = false

    private let quickColors: [Color] = [
        .black,
        .white,
        .blue,
        .red,
        .green,
        .yellow,
        .orange,
        .purple
    ]

    // Schwarz/Weiß ergeben bei einem Textmarker keinen Sinn — eigene Palette
    // mit den üblichen Leuchtfarben stattdessen.
    private let highlighterColors: [Color] = [
        .yellow,
        .green,
        .pink,
        .orange,
        .cyan,
        .purple
    ]

    private var colorsForActiveTool: [Color] {
        activeTool == .marker ? highlighterColors : quickColors
    }

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
         eraserWidth: Binding<CGFloat>? = nil,
         rulerActive: Binding<Bool> = .constant(false),
         shapeSnapEnabled: Binding<Bool> = .constant(false),
         darkDrawingMode: Bool = false,
         showRuler: Bool = true,
         onToolChanged: ((PKTool) -> Void)? = nil) {
        self._activeTool = activeTool
        self._selectedColor = selectedColor
        self._selectedWidth = selectedWidth
        self._eraserType = eraserType
        if let ew = eraserWidth {
            self._eraserWidth = ew
            self.usesLocalEraserWidth = false
        } else {
            self._eraserWidth = .constant(16.0)
            self.usesLocalEraserWidth = true
        }
        self._rulerActive = rulerActive
        self._shapeSnapEnabled = shapeSnapEnabled
        self.darkDrawingMode = darkDrawingMode
        self.showRuler = showRuler
        self.onToolChanged = onToolChanged
    }

    var onPaste: (() -> Void)? = nil
    var onTextRecognition: (() -> Void)? = nil
    var onMathRecognition: (() -> Void)? = nil
    var onScientificCalculator: (() -> Void)? = nil
    var onOpenCircuits: (() -> Void)? = nil
    var onImportDocument: (() -> Void)? = nil
    var onImportNextcloud: (() -> Void)? = nil
    var onImportGoogleDrive: (() -> Void)? = nil
    var onCloudSettings: (() -> Void)? = nil
    var onToggleAI: (() -> Void)? = nil
    var onCamera: (() -> Void)? = nil
    var onScanDocument: (() -> Void)? = nil
    var onCameraVideo: (() -> Void)? = nil
    var onYouTube: (() -> Void)? = nil
    var onWebClipper: (() -> Void)? = nil

    init(vm: InfiniteNotebookViewModel,
         onNextcloud: (() -> Void)? = nil,
         onGoogleDrive: (() -> Void)? = nil,
         onCloudSettings: (() -> Void)? = nil) {
        self._activeTool = Binding(get: { vm.activeTool }, set: { vm.activeTool = $0 })
        self._selectedColor = Binding(get: { vm.selectedColor }, set: { vm.selectedColor = $0 })
        self._selectedWidth = Binding(get: { vm.selectedWidth }, set: { vm.selectedWidth = $0 })
        self._eraserType = Binding(get: { vm.eraserType }, set: { vm.eraserType = $0 })
        self._eraserWidth = Binding(get: { vm.eraserWidth }, set: { vm.eraserWidth = $0 })
        self.usesLocalEraserWidth = false
        self._rulerActive = Binding(get: { vm.rulerActive }, set: { vm.rulerActive = $0 })
        self._shapeSnapEnabled = Binding(get: { vm.shapeSnapEnabled }, set: { vm.shapeSnapEnabled = $0 })
        self.darkDrawingMode = vm.darkDrawingMode
        self.showRuler = true
        self.onToolChanged = nil
        self.onPaste = { [weak vm] in vm?.triggerPaste = true }
        self.onTextRecognition = { [weak vm] in vm?.triggerHandwritingRecognition = true }
        self.onMathRecognition = { [weak vm] in vm?.triggerMathRecognition = true }
        self.onScientificCalculator = { [weak vm] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                vm?.toggleScientificCalculator()
            }
        }
        self.onOpenCircuits = { [weak vm] in vm?.showCircuitPicker = true }
        self.onImportDocument = { [weak vm] in vm?.showPDFPicker = true }
        self.onImportNextcloud = onNextcloud
        self.onImportGoogleDrive = onGoogleDrive
        self.onCloudSettings = onCloudSettings
        self.onToggleAI = { [weak vm] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                vm?.showAISidebar.toggle()
            }
        }
        self.onCamera = { [weak vm] in vm?.showCameraPhoto = true }
        self.onScanDocument = { [weak vm] in vm?.showDocumentScanner = true }
        self.onCameraVideo = { [weak vm] in vm?.showCameraVideo = true }
        self.onYouTube = { [weak vm] in vm?.showYouTubeEmbed = true }
        self.onWebClipper = { [weak vm] in vm?.showWebClipper = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Werkzeug, Farbe, Strichstärke & Lineal — alles, was das
            // aktuelle Zeichenwerkzeug betrifft.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Tool selector
                    HStack(spacing: 3) {
                        ForEach(CanvasToolType.allCases.filter { $0 != .pan }) { tool in
                            Button {
                                if activeTool == tool && tool == .eraser {
                                    eraserType = eraserType == .vector ? .bitmap : .vector
                                } else {
                                    activeTool = tool
                                }
                                notifyToolChange()
                            } label: {
                                VStack(spacing: 1) {
                                    Image(systemName: tool.iconName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 34, height: 26)
                                        .background(
                                            activeTool == tool ?
                                            Color.accentColor : Color(uiColor: .tertiarySystemFill)
                                        )
                                        .foregroundColor(
                                            activeTool == tool ?
                                            Color.white : Color.primary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    if activeTool == tool && tool == .eraser {
                                        Text(eraserType == .vector ? "Strich" : "Pixel")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 34, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tool.rawValue)
                        }
                    }
                    .fixedSize()

                    if activeTool != .eraser && activeTool != .lasso && activeTool != .pan && activeTool != .textSelect {
                        Divider()
                            .frame(height: 22)

                        // Quick Color palette
                        HStack(spacing: 5) {
                            ForEach(colorsForActiveTool, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                    notifyToolChange()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                                            )

                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(color == .white || color == .yellow ? .black : .white)
                                        }
                                    }
                                    .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Farbe")
                            }

                            // Native ColorPicker for unlimited color options
                            ColorPicker("", selection: Binding(get: { selectedColor }, set: { selectedColor = $0; notifyToolChange() }))
                                .labelsHidden()
                                .scaleEffect(0.8)
                                .frame(width: 24, height: 24)
                        }
                        .fixedSize()

                        Divider()
                            .frame(height: 22)

                        // Stroke width buttons
                        HStack(spacing: 6) {
                            ForEach(strokeWidths, id: \.width) { item in
                                Button {
                                    selectedWidth = item.width
                                    notifyToolChange()
                                } label: {
                                    Circle()
                                        .fill(selectedWidth == item.width ? Color.accentColor : Color.primary.opacity(0.45))
                                        .frame(width: item.dotSize, height: item.dotSize)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            selectedWidth == item.width ?
                                            Color.accentColor.opacity(0.2) : Color.clear
                                        )
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.label)
                            }
                        }
                        .fixedSize()
                    } else if activeTool == .eraser {
                        Divider()
                            .frame(height: 22)

                        // Eraser mode switcher (Pixel vs Strich)
                        HStack(spacing: 4) {
                            Button {
                                eraserType = .bitmap
                                notifyToolChange()
                            } label: {
                                Text("Pixel")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(eraserType == .bitmap ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                    .foregroundColor(eraserType == .bitmap ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                eraserType = .vector
                                notifyToolChange()
                            } label: {
                                Text("Strich")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(eraserType == .vector ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                    .foregroundColor(eraserType == .vector ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .fixedSize()

                        Divider()
                            .frame(height: 22)

                        // Continuous Eraser Size Slider
                        HStack(spacing: 8) {
                            let currentW = usesLocalEraserWidth ? localEraserWidth : eraserWidth
                            let previewDiameter = max(4, min(22, currentW * 0.42))

                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.55), lineWidth: 1.5)
                                    .background(Circle().fill(Color.accentColor.opacity(0.22)))
                                    .frame(width: previewDiameter, height: previewDiameter)
                            }
                            .frame(width: 24, height: 24)

                            Slider(
                                value: Binding(
                                    get: { usesLocalEraserWidth ? localEraserWidth : eraserWidth },
                                    set: { newVal in
                                        if usesLocalEraserWidth {
                                            localEraserWidth = newVal
                                        } else {
                                            eraserWidth = newVal
                                        }
                                        notifyToolChange()
                                    }
                                ),
                                in: 4...64
                            )
                            .frame(width: 135)

                            Text("\(Int(currentW.rounded())) pt")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 34, alignment: .leading)
                        }
                        .fixedSize()
                    }

                    if showRuler {
                        Divider()
                            .frame(height: 22)

                        // Lineal (Ruler) Toggle
                        Button {
                            rulerActive.toggle()
                        } label: {
                            Image(systemName: "ruler")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 30, height: 28)
                                .background(rulerActive ? Color.brown : Color(uiColor: .tertiarySystemFill))
                                .foregroundColor(rulerActive ? Color.white : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Lineal")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: 40)

            Divider()

            // Row 2: Erkennung (Formen/Mathe) & Import (Schaltplan/Dateien/
            // Nextcloud/Kamera/Scannen/YouTube/WebView) — smarte Aktionen,
            // unabhängig vom aktuell gewählten Zeichenwerkzeug.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if activeTool == .lasso {
                        Button {
                            onPaste?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Einfügen")
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(height: 28)
                            .background(Color.green)
                            .foregroundColor(Color.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Einfügen")

                        Divider()
                            .frame(height: 20)
                    }

                    // Erkennung: Formen, Mathe
                    Button {
                        shapeSnapEnabled.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: shapeSnapEnabled ? "square.and.circle.fill" : "square.and.circle")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Formen")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 28)
                        .background(shapeSnapEnabled ? Color.orange : Color(uiColor: .tertiarySystemFill))
                        .foregroundColor(shapeSnapEnabled ? Color.white : Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Formen-Korrektur")

                    // Untermenü: Technik & Mathe (Taschenrechner, Handschrift-Mathe, Schaltungen)
                    Menu {
                        Button {
                            onScientificCalculator?()
                        } label: {
                            Label("Wissenschaftlicher Taschenrechner", systemImage: "plus.forwardslash.minus")
                        }

                        Button {
                            onMathRecognition?()
                        } label: {
                            Label("Mathe Handschrifterkennung", systemImage: "function")
                        }

                        Button {
                            onOpenCircuits?()
                        } label: {
                            Label("Schaltpläne & Schaltsymbole…", systemImage: "bolt.badge.clock")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.badge.clock")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Technik")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 28)
                        .background(Color.indigo)
                        .foregroundColor(Color.white)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Technik & Mathe")

                    Divider()
                        .frame(height: 20)

                    // Untermenü: Dateien (iCloud Drive / Lokal, Nextcloud, Google Drive)
                    Menu {
                        Button {
                            onImportDocument?()
                        } label: {
                            Label("iCloud Drive / Dateien-App…", systemImage: "folder.badge.plus")
                        }

                        Button {
                            onImportNextcloud?()
                        } label: {
                            Label("Nextcloud…", systemImage: "icloud.and.arrow.down")
                        }

                        Button {
                            onImportGoogleDrive?()
                        } label: {
                            Label("Google Drive…", systemImage: "externaldrive.badge.icloud")
                        }

                        Divider()

                        Button {
                            onCloudSettings?()
                        } label: {
                            Label("Cloud & Synchronisation verwalten…", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Dateien")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 28)
                        .background(Color.teal)
                        .foregroundColor(Color.white)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Dateien: iCloud Drive, Nextcloud, Google Drive")

                    // Untermenü: Kamera (Foto, Dokument scannen, Video)
                    Menu {
                        Button {
                            onCamera?()
                        } label: {
                            Label("Foto mit Kamera aufnehmen…", systemImage: "camera")
                        }

                        Button {
                            onScanDocument?()
                        } label: {
                            Label("Dokument oder Tafel scannen…", systemImage: "doc.viewfinder")
                        }

                        Button {
                            onCameraVideo?()
                        } label: {
                            Label("Video mit Kamera aufnehmen…", systemImage: "video")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "camera")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Kamera")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 28)
                        .background(Color.pink)
                        .foregroundColor(Color.white)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Kamera: Foto, Scannen und Video")

                    // Untermenü: WebView (WebClipper & YouTube)
                    Menu {
                        Button {
                            onWebClipper?()
                        } label: {
                            Label("Webseite & Screenshot mit OCR…", systemImage: "globe.badge.chevron.backward")
                        }

                        Button {
                            onYouTube?()
                        } label: {
                            Label("YouTube-Video einbetten…", systemImage: "play.rectangle")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.system(size: 12, weight: .semibold))
                            Text("WebView")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(height: 28)
                        .background(Color.mint)
                        .foregroundColor(Color.white)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("WebView: Webseite mit OCR und YouTube Video")
                    // KI-Assistent ist bewusst nicht hier — der Toggle lebt oben in der
                    // Navigationsleiste bei den anderen Modus-Schaltern (Suche, Dunkelmodus).
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: 36)
        }
    }

    private func notifyToolChange() {
        let ew = usesLocalEraserWidth ? localEraserWidth : eraserWidth
        let tool = makePKTool(
            tool: activeTool,
            color: selectedColor,
            width: selectedWidth,
            eraserType: eraserType,
            eraserWidth: ew,
            darkDrawingMode: darkDrawingMode
        )
        onToolChanged?(tool)
    }
}

// MARK: - MovieTransferable

struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension))
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

// MARK: - NotebookPDFExportSheet

/// Modal sheet for configuring and triggering PDF export (All pages, page range, or visual custom snippet)
struct NotebookPDFExportSheet: View {

    enum ExportMode: String, CaseIterable, Identifiable {
        case all    = "Ganzes Blatt"
        case pages  = "Seitenbereich"
        case custom = "Ausschnitt"

        var id: String { rawValue }
    }

    let documentName: String
    let totalPages: Int
    let currentPage: Int

    @State private var exportMode: ExportMode = .all
    @State private var startPage: Int
    @State private var endPage: Int
    @State private var cropToExactHeight: Bool = true

    let onExport: (_ scope: NotebookPDFExportScope, _ cropToExactHeight: Bool) -> Void
    let onSelectRangeInNotebook: () -> Void
    let onCancel: () -> Void

    init(
        documentName: String,
        totalPages: Int,
        currentPage: Int,
        initialStartPage: Int? = nil,
        initialEndPage: Int? = nil,
        onExport: @escaping (_ scope: NotebookPDFExportScope, _ cropToExactHeight: Bool) -> Void,
        onSelectRangeInNotebook: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.documentName = documentName
        self.totalPages = max(1, totalPages)
        self.currentPage = max(1, min(currentPage, totalPages))
        _startPage = State(initialValue: max(1, min(initialStartPage ?? 1, totalPages)))
        _endPage = State(initialValue: max(1, min(initialEndPage ?? totalPages, totalPages)))
        self.onExport = onExport
        self.onSelectRangeInNotebook = onSelectRangeInNotebook
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Document Info
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(documentName)
                                .font(.headline)
                                .lineLimit(1)

                            Text("\(totalPages) A4-Seite\(totalPages > 1 ? "n" : "") • DIN A4 (595 × 842 pt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Export Mode Picker
                Section("Export-Bereich") {
                    Picker("Modus", selection: $exportMode) {
                        ForEach(ExportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)
                }

                // MARK: - Mode Details
                switch exportMode {
                case .all:
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Alle \(totalPages) Seiten werden vollständig exportiert.")
                                .font(.subheadline)
                        }
                    }

                case .pages:
                    Section("Seiten auswählen") {
                        Stepper(value: $startPage, in: 1...endPage) {
                            HStack {
                                Text("Startseite:")
                                Spacer()
                                Text("Seite \(startPage)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }

                        Stepper(value: $endPage, in: startPage...totalPages) {
                            HStack {
                                Text("Endseite:")
                                Spacer()
                                Text("Seite \(endPage)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }

                        // Quick Selectors
                        HStack(spacing: 8) {
                            Button("Aktuelle Seite (\(currentPage))") {
                                startPage = currentPage
                                endPage = currentPage
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            if totalPages > 1 {
                                Button("S. 1 bis \(currentPage)") {
                                    startPage = 1
                                    endPage = currentPage
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)

                                Button("Alle (1..\(totalPages))") {
                                    startPage = 1
                                    endPage = totalPages
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)

                        let selectedCount = max(1, endPage - startPage + 1)
                        Text("Exportiert \(selectedCount) von \(totalPages) Seite\(totalPages > 1 ? "n" : "").")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                case .custom:
                    Section("Freier Bereich (Start- & Endpunkt)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Möchtest du nur eine bestimmte Skizze, Aufgabe oder einen Abschnitt exportieren? Markiere Startpunkt und Endpunkt direkt im Notizbuch.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                onSelectRangeInNotebook()
                            } label: {
                                Label("Start- & Endpunkt im Notizbuch wählen…", systemImage: "crop")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)

                        Toggle("Ausschnitt-Höhe anpassen (keine leeren Ränder)", isOn: $cropToExactHeight)
                            .font(.subheadline)
                    }
                }

                // MARK: - Action Buttons
                Section {
                    Button {
                        switch exportMode {
                        case .all:
                            onExport(.allPages, false)
                        case .pages:
                            onExport(.pageRange(startPage: startPage, endPage: endPage), false)
                        case .custom:
                            onSelectRangeInNotebook()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label(exportMode == .custom ? "Bereich im Notizbuch öffnen" : "PDF erstellen & teilen",
                                  systemImage: exportMode == .custom ? "crop" : "square.and.arrow.up.fill")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("PDF Exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        onCancel()
                    }
                }
            }
        }
    }
}

