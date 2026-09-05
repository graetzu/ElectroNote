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
    @State private var itemToRename: DocumentItem?
    @State private var renameText = ""
    @State private var showTrash = false
    @State private var showTagBrowser = false
    @State private var itemForTagEditor: DocumentItem?

    // Observe metaStore changes so favorites/tags update live
    @ObservedObject private var metaStore = ItemMetadataStore.shared

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
        .listStyle(.sidebar)
        .animation(.default, value: viewModel.items)
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
            Image(systemName: "folder")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Noch leer")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tippe auf **+** um einen Ordner oder eine Notiz anzulegen.")
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
            LiveCastBadgeButton()

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

            Menu {
                Button { showNextcloud = true } label: {
                    Label("Nextcloud", systemImage: "icloud")
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
