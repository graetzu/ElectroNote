import PencilKit

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published private(set) var drawing = PKDrawing()
    @Published private(set) var saveState: SaveState = .saved
    @Published var pencilOnly: Bool = true

    let item: DocumentItem
    private var saveTask: Task<Void, Never>?

    enum SaveState {
        case saved, pending

        var label: String {
            switch self {
            case .saved:   return "Gespeichert"
            case .pending: return "Nicht gespeichert"
            }
        }
    }

    private var drawingURL: URL {
        item.path.appendingPathComponent("drawing.pkdrawing")
    }

    init(item: DocumentItem) {
        self.item = item
        load()
    }

    func drawingDidChange(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        saveState = .pending
        scheduleAutosave()
    }

    func save() {
        guard saveState == .pending else { return }
        do {
            try drawing.dataRepresentation().write(to: drawingURL, options: .atomic)
            saveState = .saved
        } catch {
            // state stays .pending — retry on next autosave
        }
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: drawingURL),
              let loaded = try? PKDrawing(data: data) else { return }
        drawing = loaded
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
