import SwiftUI

struct ClipArtPickerView: View {
    let onInsert: (ClipArtEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ClipArtEntry.Category = .electrical
    @State private var searchText = ""

    private var entries: [ClipArtEntry] {
        if !searchText.isEmpty { return ClipArtLibrary.search(searchText) }
        return ClipArtLibrary.catalog.filter { $0.category == selectedCategory }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category tabs (hidden during search)
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ClipArtEntry.Category.allCases, id: \.self) { cat in
                                Button {
                                    selectedCategory = cat
                                } label: {
                                    Text(cat.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(selectedCategory == cat
                                                      ? Color.accentColor
                                                      : Color(.secondarySystemFill))
                                        )
                                        .foregroundStyle(selectedCategory == cat ? .white : .primary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    Divider()
                }

                // Symbol grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(entries) { entry in
                            Button {
                                onInsert(entry)
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: entry.id)
                                        .font(.system(size: 32))
                                        .frame(width: 52, height: 52)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemFill))
                                        )
                                    Text(entry.label)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Symbol einfügen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Symbol suchen…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
