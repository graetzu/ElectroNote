import SwiftUI

struct BrowserSidebarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var selectedItem: DocumentItem?

    @State private var showNewFolder = false
    @State private var showNewNote = false
    @State private var itemToRename: DocumentItem?
    @State private var renameText = ""

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
        .sheet(isPresented: $showNewNote) {
            NewItemSheet(title: "Neue Notiz", placeholder: "Notizname") {
                viewModel.createNote(named: $0)
            }
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
            ForEach(viewModel.items) { item in
                BrowserRowView(item: item, isSelected: selectedItem?.id == item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { handleTap(on: item) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { remove(item) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .contextMenu { contextMenu(for: item) }
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: viewModel.items)
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

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button { showNewFolder = true } label: {
                    Label("Neuer Ordner", systemImage: "folder.badge.plus")
                }
                Button { showNewNote = true } label: {
                    Label("Neue Notiz", systemImage: "note.text.badge.plus")
                }
                Divider()
                Button {} label: {
                    Label("PDF importieren…", systemImage: "doc.badge.plus")
                }
                .disabled(true)
            } label: {
                Image(systemName: "plus")
            }
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
        }
    }

    private func remove(_ item: DocumentItem) {
        if selectedItem?.id == item.id { selectedItem = nil }
        viewModel.delete([item])
    }
}
