import SwiftUI

struct TagBrowserView: View {
    var onOpenItem: ((String) -> Void)? = nil

    @ObservedObject private var store = ItemMetadataStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var filteredTags: [String] {
        let all = store.allTags()
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.allTags().isEmpty {
                    emptyState
                } else {
                    tagList
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Tag suchen…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var tagList: some View {
        List(filteredTags, id: \.self) { tag in
            NavigationLink(destination: TagItemsView(tag: tag, onOpenItem: openItem)) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(tagColor(for: tag))
                    Text(tag)
                    Spacer()
                    Text("\(store.items(withTag: tag).count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Keine Tags vorhanden")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tags können über das Kontextmenü eines Elements hinzugefügt werden.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openItem(_ relPath: String) {
        dismiss()
        onOpenItem?(relPath)
    }

    // MARK: - Helpers

    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal]
        return colors[abs(tag.hashValue) % colors.count]
    }
}

// MARK: - TagItemsView

struct TagItemsView: View {
    let tag: String
    var onOpenItem: ((String) -> Void)? = nil

    @ObservedObject private var store = ItemMetadataStore.shared

    var body: some View {
        let relPaths = store.items(withTag: tag)
        List(relPaths, id: \.self) { relPath in
            tagItemRow(relPath: relPath)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(tag)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if relPaths.isEmpty {
                Text("Keine Elemente mit diesem Tag")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tagItemRow(relPath: String) -> some View {
        let lastComponent = (relPath as NSString).lastPathComponent
        let displayName = lastComponent
            .replacingOccurrences(of: ".enote", with: "")
            .replacingOccurrences(of: ".pdf", with: "")
        let folderPath = (relPath as NSString).deletingLastPathComponent
        let isNote = lastComponent.hasSuffix(".enote")
        let isPDF  = lastComponent.hasSuffix(".pdf")

        return Button {
            onOpenItem?(relPath)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isNote ? "note.text" : (isPDF ? "doc.fill" : "folder.fill"))
                    .foregroundStyle(isNote ? .blue : (isPDF ? .red : .yellow))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !folderPath.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(folderPath.replacingOccurrences(of: "/", with: " › "))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
