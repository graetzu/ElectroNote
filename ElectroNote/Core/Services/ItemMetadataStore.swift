import Foundation

// Stores per-item metadata (tags + favorites) keyed by relative path from rootURL.
// Persisted as .electro_meta.json at the root level.

final class ItemMetadataStore: ObservableObject {
    static let shared = ItemMetadataStore()

    struct Meta: Codable {
        var tags:      [String: [String]] = [:]   // relPath → [tag]
        var favorites: [String] = []               // relPaths
    }

    @Published private(set) var meta = Meta() { didSet { save() } }
    private var rootURL: URL?
    private var fileURL: URL? { rootURL?.appendingPathComponent(".electro_meta.json") }

    func configure(rootURL: URL) {
        self.rootURL = rootURL
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Meta.self, from: data) {
            meta = decoded
        }
    }

    func tags(for relPath: String) -> [String]   { meta.tags[relPath] ?? [] }
    func isFavorite(_ relPath: String) -> Bool    { meta.favorites.contains(relPath) }
    func allTags() -> [String]                    { Array(Set(meta.tags.values.flatMap { $0 })).sorted() }

    func setTags(_ tags: [String], for relPath: String) {
        var m = meta
        m.tags[relPath] = tags.isEmpty ? nil : tags
        meta = m
    }
    func addTag(_ tag: String, for relPath: String) {
        var t = tags(for: relPath)
        guard !t.contains(tag) else { return }
        t.append(tag)
        setTags(t, for: relPath)
    }
    func removeTag(_ tag: String, for relPath: String) {
        setTags(tags(for: relPath).filter { $0 != tag }, for: relPath)
    }
    func toggleFavorite(_ relPath: String) {
        var m = meta
        if m.favorites.contains(relPath) { m.favorites.removeAll { $0 == relPath } }
        else                              { m.favorites.insert(relPath, at: 0) }
        meta = m
    }
    func items(withTag tag: String) -> [String] {
        meta.tags.filter { $0.value.contains(tag) }.map(\.key).sorted()
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
