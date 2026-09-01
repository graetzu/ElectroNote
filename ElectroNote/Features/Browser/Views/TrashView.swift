import SwiftUI

struct TrashView: View {
    @ObservedObject private var trashManager = TrashManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showEmptyConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if trashManager.items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .navigationTitle("Papierkorb")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .alert("Papierkorb leeren?", isPresented: $showEmptyConfirm) {
                Button("Leeren", role: .destructive) { trashManager.emptyTrash() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle \(trashManager.items.count) Elemente werden unwiderruflich gelöscht.")
            }
            .alert("Fehler", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var itemList: some View {
        List {
            ForEach(trashManager.items.sorted { $0.trashedAt > $1.trashedAt }) { item in
                trashRow(item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { permanentDelete(item) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button { restore(item) } label: {
                            Label("Wiederherstellen", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func trashRow(_ item: TrashItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.body)
            HStack {
                Text(item.originalRelPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(relativeDate(item.trashedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Papierkorb ist leer")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Schließen") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Leeren") { showEmptyConfirm = true }
                .disabled(trashManager.items.isEmpty)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func restore(_ item: TrashItem) {
        do { try trashManager.restore(item) }
        catch { errorMessage = error.localizedDescription }
    }

    private func permanentDelete(_ item: TrashItem) {
        do { try trashManager.deletePermanently(item) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
