import Foundation

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var items: [DocumentItem] = []
    @Published var currentPath: URL
    @Published var error: String?

    private(set) var fileService: FileServiceProtocol
    private var navStack: [URL] = []

    let metaStore = ItemMetadataStore.shared

    // MARK: - Global Search Across All Documents & Handwriting
    @Published var searchText: String = "" {
        didSet {
            performSearchDebounced()
        }
    }
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching: Bool = false
    private var searchTask: Task<Void, Never>?

    func performSearchDebounced() {
        searchTask?.cancel()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }

            let results = await NoteSearchDatabase.shared.search(query: q)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    func findDocumentItem(for docPath: String) -> DocumentItem? {
        let all = fileService.listAllDocuments()
        return all.first { $0.path.path == docPath }
    }

    var isAtRoot: Bool { currentPath == fileService.rootURL }
    var currentFolderName: String { isAtRoot ? "ElectroNote" : currentPath.lastPathComponent }
    var rootURL: URL { fileService.rootURL }

    init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
        self.currentPath = fileService.rootURL
        metaStore.configure(rootURL: fileService.rootURL)
        TrashManager.shared.configure(rootURL: fileService.rootURL)
        loadItems()
    }

    func loadItems() {
        items = fileService.listItems(at: currentPath)
    }

    func navigate(into folder: DocumentItem) {
        navStack.append(currentPath)
        currentPath = folder.path
        loadItems()
    }

    func navigateUp() {
        guard let prev = navStack.popLast() else { return }
        currentPath = prev
        loadItems()
    }

    func createFolder(named name: String) {
        guard !name.isEmpty else { return }
        do {
            _ = try fileService.createFolder(named: name, at: currentPath)
            loadItems()
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func createNote(named name: String) -> DocumentItem? {
        createDocument(named: name, type: .notebook)
    }

    @discardableResult
    func createDocument(named name: String, type: DocumentType) -> DocumentItem? {
        guard !name.isEmpty else { return nil }
        do {
            let item = try fileService.createDocument(named: name, type: type, at: currentPath)
            loadItems()
            return item
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func rename(item: DocumentItem, to newName: String) {
        guard !newName.isEmpty else { return }
        do {
            _ = try fileService.rename(item: item, to: newName)
            loadItems()
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func importPDF(from url: URL) -> DocumentItem? {
        do {
            let item = try fileService.importPDF(from: url, to: currentPath)
            loadItems()
            return item
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func listAllDocuments() -> [DocumentItem] {
        fileService.listAllDocuments()
    }

    func listAllFolders() -> [URL] {
        fileService.listAllFolders()
    }

    func displayPath(for item: DocumentItem) -> String {
        fileService.displayPath(for: item)
    }

    func delete(_ items: [DocumentItem]) {
        for item in items {
            do {
                try TrashManager.shared.moveToTrash(item: item, rootURL: fileService.rootURL)
            } catch {
                // Fall back to permanent delete if trash fails
                do { try fileService.delete(item: item) }
                catch { self.error = error.localizedDescription }
            }
        }
        loadItems()
    }

    // MARK: - Cross-folder navigation

    /// Navigates to the item at `relPath` (relative to rootURL) and returns it for selection.
    /// Intermediate folder components are navigated automatically.
    @discardableResult
    func navigateTo(relPath: String) -> DocumentItem? {
        let components = relPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return nil }

        // Reset to root
        navStack.removeAll()
        currentPath = fileService.rootURL
        loadItems()

        // Walk into each folder until we reach the parent of the target
        for folder in components.dropLast() {
            guard let folderItem = items.first(where: { $0.name == folder && $0.isFolder }) else { return nil }
            navStack.append(currentPath)
            currentPath = folderItem.path
            loadItems()
        }

        let targetName = components.last!
        return items.first(where: { $0.path.lastPathComponent == targetName })
    }

    // MARK: - Favorites

    func relPath(for item: DocumentItem) -> String {
        let rootPath = fileService.rootURL.path
        let itemPath = item.path.path
        guard itemPath.hasPrefix(rootPath) else { return item.path.lastPathComponent }
        let dropped = itemPath.dropFirst(rootPath.count)
        return dropped.hasPrefix("/") ? String(dropped.dropFirst()) : String(dropped)
    }

    func isFavorite(_ item: DocumentItem) -> Bool {
        metaStore.isFavorite(relPath(for: item))
    }

    func toggleFavorite(_ item: DocumentItem) {
        metaStore.toggleFavorite(relPath(for: item))
    }
}
