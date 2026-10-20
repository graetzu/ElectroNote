import SwiftUI

struct BrowserSidebarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var selectedItem: DocumentItem?
    @Binding var sidebarVisibility: NavigationSplitViewVisibility

    @State private var showNewFolder = false
    @State private var showNewNote = false
    @State private var showDocTypePicker = false
    @State private var pendingDocType: DocumentType? = nil
    @State private var showPDFPicker = false
    @State private var showNextcloud = false
    @State private var showSettings = false
    @State private var itemToRename: DocumentItem?
    @State private var renameText = ""
    @State private var showTrash = false
    @State private var showTagBrowser = false
    @State private var itemForTagEditor: DocumentItem?
    @State private var showCollabSheet = false
    @State private var collabInitialTab = 1
    @State private var showLiveCastSheet = false

    // Observe metaStore changes so favorites/tags update live
    @ObservedObject private var metaStore = ItemMetadataStore.shared
    @ObservedObject private var collab = LiveCollabSessionManager.shared
    @ObservedObject private var liveCast = LiveCastServer.shared

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(viewModel.currentFolderName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .searchable(text: $viewModel.searchText, prompt: "Notizen, Handschrift & Dokumente…")
        .refreshable { viewModel.loadItems() }
        .sheet(isPresented: $showNewFolder) {
            NewItemSheet(title: "Neuer Ordner", placeholder: "Ordnername") {
                viewModel.createFolder(named: $0)
            }
        }
        .sheet(isPresented: $showDocTypePicker) {
            DocumentTypePickerView { docType in
                pendingDocType = docType
                showDocTypePicker = false
                // Short delay lets the picker dismiss before the name sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewNote = true
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewNote) {
            NewItemSheet(title: "Neues Dokument", placeholder: "Name") {
                let created: DocumentItem?
                if let type = pendingDocType {
                    created = viewModel.createDocument(named: $0, type: type)
                } else {
                    created = viewModel.createNote(named: $0)
                }
                pendingDocType = nil
                if let item = created {
                    selectedItem = item
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarVisibility = .detailOnly
                    }
                }
            }
        }
        .sheet(isPresented: $showPDFPicker) {
            DocumentPicker(contentTypes: DocumentConverter.supportedTypes + [.image]) { url in
                ExternalFileImportManager.shared.handleIncomingURL(url)
            }
        }
        .sheet(isPresented: $showNextcloud) {
            SyncSettingsView(localRoot: viewModel.currentPath) { pdfURL in
                if let item = viewModel.importPDF(from: pdfURL) {
                    selectedItem = item
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarVisibility = .detailOnly
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            AppSettingsView { pdfURL in
                if let item = viewModel.importPDF(from: pdfURL) {
                    selectedItem = item
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarVisibility = .detailOnly
                    }
                }
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
                .onDisappear { viewModel.loadItems() }
        }
        .sheet(isPresented: $showTagBrowser) {
            TagBrowserView { relPath in
                if let item = viewModel.navigateTo(relPath: relPath) {
                    selectedItem = item.isFolder ? nil : item
                    if !item.isFolder {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarVisibility = .detailOnly
                        }
                    }
                }
            }
        }
        .sheet(item: $itemForTagEditor) { item in
            TagEditorView(item: item, relPath: viewModel.relPath(for: item))
        }
        .sheet(isPresented: $showCollabSheet) {
            LiveCollabSheetView(
                documentName: selectedItem?.name ?? "Live-Zusammenarbeit",
                documentType: selectedItem?.type.collabDocumentType ?? .note,
                initialTab: collabInitialTab
            )
        }
        .sheet(isPresented: $showLiveCastSheet) {
            LiveCastSheetView()
        }
        .alert("Umbenennen", isPresented: Binding(
            get: { itemToRename != nil },
            set: { if !$0 { itemToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                if let item = itemToRename { viewModel.rename(item: item, to: renameText.trimmed) }
                itemToRename = nil
            }
            Button("Abbrechen", role: .cancel) { itemToRename = nil }
        }
        .alert("Fehler", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Subviews

    private var itemList: some View {
        List {
            if !viewModel.searchText.isEmpty {
                // Section 1: Handschrift & Inhalte
                if !viewModel.searchResults.isEmpty {
                    Section("Handschrift & Inhalte (\(viewModel.searchResults.count))") {
                        ForEach(viewModel.searchResults) { hit in
                            searchResultRow(hit)
                        }
                    }
                } else if !viewModel.isSearching {
                    Section {
                        Text("Keine Treffer in Inhalten für „\(viewModel.searchText)“")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Section 2: Dateien & Ordner mit passendem Namen
                let matchingItems = viewModel.items.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
                if !matchingItems.isEmpty {
                    Section("Dateien & Ordner (\(matchingItems.count))") {
                        ForEach(matchingItems) { item in
                            itemRow(item)
                        }
                    }
                }
            } else {
                // First option in sidebar: Create New Document
                Section {
                    Button {
                        showDocTypePicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text("Neues Dokument erstellen…")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                // Favorites section – only at root
                if viewModel.isAtRoot {
                    let favorites = viewModel.items.filter { viewModel.isFavorite($0) }
                    if !favorites.isEmpty {
                        Section("Favoriten") {
                            ForEach(favorites) { item in
                                itemRow(item)
                            }
                        }
                    }
                }

                // All items section
                Section(viewModel.isAtRoot ? "Alle Elemente" : "") {
                    ForEach(viewModel.items) { item in
                        itemRow(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: viewModel.items)
    }

    private func searchResultRow(_ hit: SearchResultItem) -> some View {
        Button {
            handleSearchResultTap(hit)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: hit.contentType.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorForContentType(hit.contentType))

                    Text(hit.documentName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(hit.contentType.localizedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForContentType(hit.contentType).opacity(0.12))
                        .foregroundColor(colorForContentType(hit.contentType))
                        .clipShape(Capsule())
                }

                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func colorForContentType(_ type: SearchContentType) -> Color {
        switch type {
        case .handwriting: return .blue
        case .text:        return .teal
        case .stickyNote:  return .orange
        case .scan:        return .indigo
        case .pdf:         return .red
        case .bookmark:    return .purple
        }
    }

    private func handleSearchResultTap(_ hit: SearchResultItem) {
        guard let doc = viewModel.findDocumentItem(for: hit.documentPath) else { return }
        selectedItem = doc
        withAnimation(.easeInOut(duration: 0.25)) {
            sidebarVisibility = .detailOnly
        }

        // Post jump notification to open document at the exact match location
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: .electroNoteJumpToSearchResult,
                object: nil,
                userInfo: [
                    "docPath": hit.documentPath,
                    "x": hit.canvasRect.origin.x,
                    "y": hit.canvasRect.origin.y,
                    "w": hit.canvasRect.width,
                    "h": hit.canvasRect.height,
                    "query": viewModel.searchText
                ]
            )
        }
    }

    private func itemRow(_ item: DocumentItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BrowserRowView(
                item: item,
                isSelected: selectedItem?.id == item.id,
                isFavorite: viewModel.isFavorite(item)
            )
            // Tag chips
            let tags = metaStore.tags(for: viewModel.relPath(for: item))
            if !tags.isEmpty {
                tagChipsRow(tags)
                    .padding(.leading, 48)
                    .padding(.bottom, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap(on: item) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { remove(item) } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .contextMenu { contextMenu(for: item) }
    }

    private func tagChipsRow(_ tags: [String]) -> some View {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal]
        return HStack(spacing: 4) {
            ForEach(tags.prefix(4), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colors[abs(tag.hashValue) % colors.count].opacity(0.15))
                    .foregroundStyle(colors[abs(tag.hashValue) % colors.count])
                    .clipShape(Capsule())
            }
            if tags.count > 4 {
                Text("+\(tags.count - 4)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Button {
                showDocTypePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Neues Dokument erstellen…")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.blue.gradient)
                .clipShape(Capsule())
            }
            .padding(.bottom, 8)

            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Noch leer")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tippe oben auf **Neues Dokument erstellen** oder **+**.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.isAtRoot {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.navigateUp()
                    selectedItem = nil
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Zurück")
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // 1. First toolbar option: Create New Document / Folder / Import
            Menu {
                Button { showDocTypePicker = true } label: {
                    Label("Neues Dokument…", systemImage: "note.text.badge.plus")
                }
                Button { showNewFolder = true } label: {
                    Label("Neuer Ordner", systemImage: "folder.badge.plus")
                }
                Divider()
                Button { showPDFPicker = true } label: {
                    Label("Datei / PDF importieren…", systemImage: "doc.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Neu")

            // 2. Live Collaboration & Cast grouped in a submenu
            Menu {
                Section("Live-Zusammenarbeit") {
                    Button {
                        collabInitialTab = 0
                        showCollabSheet = true
                    } label: {
                        Label("Sitzung hosten…", systemImage: "person.2.wave.2.fill")
                    }
                    Button {
                        collabInitialTab = 1
                        showCollabSheet = true
                    } label: {
                        Label("Sitzung beitreten…", systemImage: "arrow.right.circle.fill")
                    }
                }
                Section("Bildschirmübertragung") {
                    Button {
                        showLiveCastSheet = true
                    } label: {
                        Label(
                            liveCast.isStreaming ? "WLAN Live-Cast aktiv (\(liveCast.viewerCount))" : "WLAN Live-Übertragung (Cast)…",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if collab.sessionState == .hosting || collab.sessionState == .connected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    } else if liveCast.isStreaming {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .accessibilityLabel("Live-Menü")

            Menu {
                Button { showSettings = true } label: {
                    Label("Einstellungen & Cloud", systemImage: "gearshape")
                }
                Divider()
                Button { showNextcloud = true } label: {
                    Label("Nextcloud Direktzugriff", systemImage: "externaldrive.connected.to.line.below")
                }
                Button { showTagBrowser = true } label: {
                    Label("Tags", systemImage: "tag")
                }
                Button { showTrash = true } label: {
                    Label("Papierkorb", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Optionen")
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: DocumentItem) -> some View {
        Button {
            renameText = item.name
            itemToRename = item
        } label: {
            Label("Umbenennen", systemImage: "pencil")
        }

        Button {
            viewModel.toggleFavorite(item)
        } label: {
            Label(
                viewModel.isFavorite(item) ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen",
                systemImage: viewModel.isFavorite(item) ? "star.slash" : "star"
            )
        }

        Button {
            itemForTagEditor = item
        } label: {
            Label("Tags bearbeiten…", systemImage: "tag")
        }

        Divider()

        Button(role: .destructive) { remove(item) } label: {
            Label("Löschen", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func handleTap(on item: DocumentItem) {
        if item.isFolder {
            viewModel.navigate(into: item)
            selectedItem = nil
        } else {
            selectedItem = item
            withAnimation(.easeInOut(duration: 0.25)) {
                sidebarVisibility = .detailOnly
            }
        }
    }

    private func remove(_ item: DocumentItem) {
        if selectedItem?.id == item.id { selectedItem = nil }
        viewModel.delete([item])
    }
}
