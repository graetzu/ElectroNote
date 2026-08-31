import SwiftUI

@MainActor
final class ClipArtViewModel: ObservableObject {
    @Published var items: [ClipArtItem] = []
    @Published var selectedID: UUID?

    private let containerURL: URL
    private var currentPage: Int?
    private var saveTask: Task<Void, Never>?

    // note canvas: pageIndex = nil
    // PDF page:    pageIndex = page number
    init(containerURL: URL, pageIndex: Int? = nil) {
        self.containerURL = containerURL
        self.currentPage = pageIndex
        items = load(page: pageIndex)
    }

    // MARK: - Page switching (PDF only)

    func switchToPage(_ pageIndex: Int) {
        save(page: currentPage)
        currentPage = pageIndex
        items = load(page: pageIndex)
        selectedID = nil
    }

    // MARK: - CRUD

    func insert(_ entry: ClipArtEntry, at center: CGPoint) {
        let item = ClipArtItem(symbolName: entry.id, at: center)
        items.append(item)
        selectedID = item.id
        scheduleSave()
    }

    func move(item: ClipArtItem, by translation: CGSize) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].x += translation.width
        items[idx].y += translation.height
    }

    func commitMove() { scheduleSave() }

    func setColor(_ color: ClipArtColor, for item: ClipArtItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].colorKey = color
        scheduleSave()
    }

    func delete(_ item: ClipArtItem) {
        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = nil }
        scheduleSave()
    }

    func select(_ item: ClipArtItem) { selectedID = item.id }
    func deselect()                  { selectedID = nil }

    func saveNow() { save(page: currentPage) }

    // MARK: - Persistence

    private func load(page: Int?) -> [ClipArtItem] {
        guard let data = try? Data(contentsOf: storageURL(page: page)),
              let decoded = try? JSONDecoder().decode([ClipArtItem].self, from: data) else { return [] }
        return decoded
    }

    private func save(page: Int?) {
        saveTask?.cancel()
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL(page: page), options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.save(page: self.currentPage)
        }
    }

    private func storageURL(page: Int?) -> URL {
        if let p = page {
            return containerURL.appendingPathComponent("cliparts_p\(p).json")
        }
        return containerURL.appendingPathComponent("cliparts.json")
    }
}
