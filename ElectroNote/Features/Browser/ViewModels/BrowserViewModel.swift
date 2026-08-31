import Foundation

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var items: [DocumentItem] = []
    @Published var currentPath: URL
    @Published var error: String?

    private let fileService: FileServiceProtocol
    private var navStack: [URL] = []

    var isAtRoot: Bool { currentPath == fileService.rootURL }
    var currentFolderName: String { isAtRoot ? "ElectroNote" : currentPath.lastPathComponent }

    init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
        self.currentPath = fileService.rootURL
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

    func createNote(named name: String) {
        guard !name.isEmpty else { return }
        do {
            _ = try fileService.createNote(named: name, at: currentPath)
            loadItems()
        } catch { self.error = error.localizedDescription }
    }

    func rename(item: DocumentItem, to newName: String) {
        guard !newName.isEmpty else { return }
        do {
            _ = try fileService.rename(item: item, to: newName)
            loadItems()
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ items: [DocumentItem]) {
        for item in items {
            do { try fileService.delete(item: item) }
            catch { self.error = error.localizedDescription }
        }
        loadItems()
    }
}
