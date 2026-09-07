import SwiftUI
import PDFKit

struct IncomingFileImportSheet: View {
    let file: IncomingFileInfo
    @ObservedObject var browserVM: BrowserViewModel
    @Binding var selectedItem: DocumentItem?
    @Binding var sidebarVisibility: NavigationSplitViewVisibility

    enum ImportMode: String, CaseIterable, Identifiable {
        case newDocument = "Neues Dokument"
        case existingDocument = "In vorhandenes Dokument"

        var id: String { rawValue }
    }

    enum PDFCreationType: String, CaseIterable, Identifiable {
        case notebook = "Notizbuch (.enote)"
        case pdfDocument = "PDF-Dokument"

        var id: String { rawValue }
    }

    @State private var importMode: ImportMode = .newDocument
    @State private var documentName: String = ""
    @State private var selectedFolderURL: URL
    @State private var pdfCreationType: PDFCreationType = .notebook
    @State private var searchText: String = ""
    @State private var isProcessing: Bool = false
    @State private var processingStatus: String = ""
    @State private var errorMessage: String? = nil

    @Environment(\.dismiss) private var dismiss

    init(
        file: IncomingFileInfo,
        browserVM: BrowserViewModel,
        selectedItem: Binding<DocumentItem?>,
        sidebarVisibility: Binding<NavigationSplitViewVisibility>
    ) {
        self.file = file
        self.browserVM = browserVM
        self._selectedItem = selectedItem
        self._sidebarVisibility = sidebarVisibility
        self._documentName = State(initialValue: file.baseName)
        self._selectedFolderURL = State(initialValue: browserVM.currentPath)

        // If a document is already open, default to inserting into existing document
        if let current = selectedItem.wrappedValue, (current.type == .note || current.type == .pdf) {
            self._importMode = State(initialValue: .existingDocument)
        } else {
            self._importMode = State(initialValue: .newDocument)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        fileHeaderCard

                        Picker("Modus", selection: $importMode) {
                            ForEach(ImportMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if importMode == .newDocument {
                            newDocumentSection
                        } else {
                            existingDocumentSection
                        }
                    }
                    .padding(.vertical)
                }

                if isProcessing {
                    processingOverlay
                }
            }
            .navigationTitle("Datei empfangen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        ExternalFileImportManager.shared.dismiss()
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .alert("Fehler beim Importieren", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - File Header Card

    private var fileHeaderCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(file.iconColor.gradient)
                    .frame(width: 58, height: 58)
                    .shadow(color: file.iconColor.opacity(0.3), radius: 6, y: 3)

                Image(systemName: file.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(file.originalFilename)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(file.fileTypeDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - New Document Section

    private var newDocumentSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Als neues Dokument anlegen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(spacing: 12) {
                    // Name TextField
                    HStack {
                        Image(systemName: "pencil.line")
                            .foregroundStyle(.secondary)
                        TextField("Dokumentname", text: $documentName)
                            .textInputAutocapitalization(.words)
                        if !documentName.isEmpty {
                            Button {
                                documentName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // If file is PDF or convertible Office doc, choose format
                    if file.isPDF || file.isOfficeOrDoc {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Format")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Picker("Format", selection: $pdfCreationType) {
                                ForEach(PDFCreationType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(pdfCreationType == .notebook
                                ? "PDF wird auf einer unendlichen Leinwand platziert (beliebig viel Platz für Handschrift daneben & darunter)."
                                : "Klassische Seitenansicht mit Stift-Annotationen direkt auf den PDF-Seiten.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    // Folder selector
                    let folders = browserVM.listAllFolders()
                    if folders.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speicherort")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Picker("Ordner", selection: $selectedFolderURL) {
                                ForEach(folders, id: \.self) { folder in
                                    Text(folderName(for: folder)).tag(folder)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)

            Button {
                createNewDocument()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Neues Dokument erstellen")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 3)
            }
            .padding(.horizontal)
            .disabled(documentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Existing Document Section

    private var existingDocumentSection: some View {
        VStack(spacing: 16) {
            // Currently open document quick action
            if let current = selectedItem, (current.type == .note || current.type == .pdf) {
                currentDocumentCard(current)
            }

            // Search & list of all other documents
            VStack(alignment: .leading, spacing: 12) {
                Text("In bestehendes Dokument einfügen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Dokumente durchsuchen…", text: $searchText)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)

                let allDocs = filteredDocuments
                if allDocs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text(searchText.isEmpty ? "Keine passenden Dokumente vorhanden." : "Kein Dokument gefunden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(allDocs) { doc in
                            documentRow(doc)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func currentDocumentCard(_ current: DocumentItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Aktuell geöffnet", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }

            HStack(spacing: 12) {
                Image(systemName: current.type == .note ? "note.text" : "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name)
                        .font(.headline)
                    Text("Wird direkt am Ende dieses Dokuments eingefügt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    insertInto(target: current)
                } label: {
                    Text("Hier einfügen")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
        )
        .padding(.horizontal)
    }

    private func documentRow(_ doc: DocumentItem) -> some View {
        Button {
            insertInto(target: doc)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.type == .note ? "note.text" : "doc.richtext.fill")
                    .font(.title3)
                    .foregroundStyle(doc.type == .note ? .blue : .red)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(browserVM.displayPath(for: doc))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(formattedDate(doc.modifiedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filteredDocuments: [DocumentItem] {
        let all = browserVM.listAllDocuments().filter { $0.type == .note || $0.type == .pdf }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return all
        }
        return all.filter {
            $0.name.lowercased().contains(query) ||
            browserVM.displayPath(for: $0).lowercased().contains(query)
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white)

                Text(processingStatus.isEmpty ? "Wird verarbeitet…" : processingStatus)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Actions

    private func createNewDocument() {
        let name = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isProcessing = true
        processingStatus = "Erstelle Dokument…"

        Task {
            do {
                var finalItem: DocumentItem? = nil

                if file.isPDF {
                    if pdfCreationType == .pdfDocument {
                        let imported = try browserVM.fileService.importPDF(from: file.localURL, to: selectedFolderURL)
                        if imported.name != name {
                            finalItem = try browserVM.fileService.rename(item: imported, to: name)
                        } else {
                            finalItem = imported
                        }
                    } else {
                        // Notebook format with PDF pages embedded
                        let noteItem = try browserVM.fileService.createNote(named: name, at: selectedFolderURL)
                        let store = NotebookDocumentStore(noteURL: noteItem.path)
                        try await store.appendPDF(from: file.localURL)
                        finalItem = noteItem
                    }
                } else if file.isImage {
                    let noteItem = try browserVM.fileService.createNote(named: name, at: selectedFolderURL)
                    if let img = UIImage(contentsOfFile: file.localURL.path) {
                        let store = NotebookDocumentStore(noteURL: noteItem.path)
                        try await store.appendImage(img)
                    }
                    finalItem = noteItem
                } else if file.isOfficeOrDoc {
                    processingStatus = "Konvertiere Dokument…"
                    let pdfURL = try await DocumentConverter.shared.convertToPDF(sourceURL: file.localURL)
                    if pdfCreationType == .pdfDocument {
                        let imported = try browserVM.fileService.importPDF(from: pdfURL, to: selectedFolderURL)
                        if imported.name != name {
                            finalItem = try browserVM.fileService.rename(item: imported, to: name)
                        } else {
                            finalItem = imported
                        }
                    } else {
                        let noteItem = try browserVM.fileService.createNote(named: name, at: selectedFolderURL)
                        let store = NotebookDocumentStore(noteURL: noteItem.path)
                        try await store.appendPDF(from: pdfURL)
                        finalItem = noteItem
                    }
                }

                await MainActor.run {
                    browserVM.loadItems()
                    if let item = finalItem {
                        selectedItem = item
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarVisibility = .detailOnly
                        }
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ExternalFileImportManager.shared.dismiss()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func insertInto(target: DocumentItem) {
        isProcessing = true
        processingStatus = "Füge in \(target.name) ein…"

        Task {
            do {
                if target.type == .note {
                    if selectedItem?.id == target.id {
                        // Currently open note: copy to a dedicated temporary file so it remains valid
                        let workingURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("InsertLive_\(UUID().uuidString)_\(file.originalFilename)")
                        try FileManager.default.copyItem(at: file.localURL, to: workingURL)

                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .electroNoteInsertFileIntoOpenDocument,
                                object: nil,
                                userInfo: ["url": workingURL, "targetPath": target.path.path]
                            )
                            withAnimation(.easeInOut(duration: 0.25)) {
                                sidebarVisibility = .detailOnly
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            ExternalFileImportManager.shared.dismiss()
                            dismiss()
                        }
                        return
                    } else {
                        // Closed note: append to note bundle on disk
                        let store = NotebookDocumentStore(noteURL: target.path)
                        if file.isImage, let img = UIImage(contentsOfFile: file.localURL.path) {
                            try await store.appendImage(img)
                        } else {
                            try await store.appendPDF(from: file.localURL)
                        }
                        await MainActor.run {
                            browserVM.loadItems()
                            selectedItem = target
                            withAnimation(.easeInOut(duration: 0.25)) {
                                sidebarVisibility = .detailOnly
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            ExternalFileImportManager.shared.dismiss()
                            dismiss()
                        }
                        return
                    }
                } else if target.type == .pdf {
                    let pdfURL: URL
                    if file.isPDF {
                        pdfURL = file.localURL
                    } else {
                        processingStatus = "Konvertiere Datei in PDF…"
                        pdfURL = try await DocumentConverter.shared.convertToPDF(sourceURL: file.localURL)
                    }

                    guard let targetPDF = PDFDocument(url: target.path) else {
                        throw NSError(domain: "ElectroNote", code: -1, userInfo: [NSLocalizedDescriptionKey: "Zieldokument konnte nicht geladen werden."])
                    }
                    guard let incomingPDF = PDFDocument(url: pdfURL) else {
                        throw NSError(domain: "ElectroNote", code: -1, userInfo: [NSLocalizedDescriptionKey: "Eingefügtes Dokument konnte nicht geladen werden."])
                    }

                    for i in 0..<incomingPDF.pageCount {
                        if let page = incomingPDF.page(at: i) {
                            targetPDF.insert(page, at: targetPDF.pageCount)
                        }
                    }
                    targetPDF.write(to: target.path)

                    await MainActor.run {
                        if selectedItem?.id == target.id {
                            NotificationCenter.default.post(
                                name: .electroNoteReloadCurrentPDF,
                                object: nil,
                                userInfo: ["targetPath": target.path.path]
                            )
                        } else {
                            browserVM.loadItems()
                            selectedItem = target
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarVisibility = .detailOnly
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        ExternalFileImportManager.shared.dismiss()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func folderName(for url: URL) -> String {
        if url == browserVM.rootURL {
            return "ElectroNote (Hauptordner)"
        }
        let rootPath = browserVM.rootURL.path
        let parentPath = url.path
        if parentPath.hasPrefix(rootPath) {
            let dropped = parentPath.dropFirst(rootPath.count)
            let cleaned = dropped.hasPrefix("/") ? String(dropped.dropFirst()) : String(dropped)
            return cleaned.replacingOccurrences(of: "/", with: " > ")
        }
        return url.lastPathComponent
    }

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let df = DateFormatter()
            df.dateFormat = "'Heute,' HH:mm"
            return df.string(from: date)
        } else if cal.isDateInYesterday(date) {
            let df = DateFormatter()
            df.dateFormat = "'Gestern,' HH:mm"
            return df.string(from: date)
        } else {
            let df = DateFormatter()
            df.dateStyle = .short
            return df.string(from: date)
        }
    }
}
