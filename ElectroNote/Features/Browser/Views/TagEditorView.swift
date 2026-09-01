import SwiftUI

struct TagEditorView: View {
    let item: DocumentItem
    let relPath: String

    @ObservedObject private var store = ItemMetadataStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newTagText = ""

    private var currentTags: [String] { store.tags(for: relPath) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorhandene Tags") {
                    if currentTags.isEmpty {
                        Text("Noch keine Tags")
                            .foregroundStyle(.secondary)
                    } else {
                        tagChipsSection
                    }
                }

                Section("Neuen Tag hinzufügen") {
                    HStack {
                        TextField("Tag eingeben…", text: $newTagText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { addTag() }
                        Button("Hinzufügen", action: addTag)
                            .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Tags für \(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var tagChipsSection: some View {
        TagFlowLayout(spacing: 8) {
            ForEach(currentTags, id: \.self) { tag in
                tagChip(tag)
            }
        }
        .padding(.vertical, 4)
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
            Button {
                store.removeTag(tag, for: relPath)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tagColor(for: tag).opacity(0.15))
        .foregroundStyle(tagColor(for: tag))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(tagColor(for: tag).opacity(0.4), lineWidth: 1))
    }

    // MARK: - Actions

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        store.addTag(tag, for: relPath)
        newTagText = ""
    }

    // MARK: - Helpers

    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal]
        let index = abs(tag.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - TagFlowLayout

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            _ = maxWidth  // suppress warning
        }
    }
}
