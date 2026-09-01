import SwiftUI

// MARK: - Document types

enum DocumentType: String, CaseIterable, Identifiable {
    case notebook   = "Notizbuch"
    case pap        = "Ablaufplan (PAP)"
    case whiteboard = "Whiteboard"
    case mindmap    = "MindMap"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .notebook:   return "note.text"
        case .pap:        return "arrow.triangle.branch"
        case .whiteboard: return "rectangle.and.pencil.and.ellipsis"
        case .mindmap:    return "brain"
        }
    }

    var description: String {
        switch self {
        case .notebook:   return "Endlos langer A4-Zettel zum Schreiben und Zeichnen"
        case .pap:        return "Programmablaufplan mit Knoten und Verbindungen"
        case .whiteboard: return "Freie Zeichenfläche, beliebig zoombar"
        case .mindmap:    return "Gedankenkarte mit Ästen und Notizen"
        }
    }

    /// File extension for the package directory
    var fileExtension: String {
        switch self {
        case .notebook:   return "enote"
        case .pap:        return "epap"
        case .whiteboard: return "ewb"
        case .mindmap:    return "emm"
        }
    }

    var accentColor: Color {
        switch self {
        case .notebook:   return .blue
        case .pap:        return .orange
        case .whiteboard: return .green
        case .mindmap:    return .purple
        }
    }

    /// Corresponding DocumentItem.ItemType
    var itemType: DocumentItem.ItemType {
        switch self {
        case .notebook:   return .note
        case .pap:        return .pap
        case .whiteboard: return .whiteboard
        case .mindmap:    return .mindmap
        }
    }
}

// MARK: - Picker view

struct DocumentTypePickerView: View {
    let onSelect: (DocumentType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DocumentType.allCases) { type in
                        typeCard(type)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Dokumenttyp wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func typeCard(_ type: DocumentType) -> some View {
        Button {
            onSelect(type)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(type.accentColor)
                    .frame(height: 44)

                Text(type.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(type.accentColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
