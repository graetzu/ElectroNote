import SwiftUI

struct BrowserRowView: View {
    let item: DocumentItem
    var isSelected: Bool = false
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 36, height: 36)
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .background(Circle().fill(iconColor).padding(-2))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text(item.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !item.syncStatus.systemImage.isEmpty {
                Image(systemName: item.syncStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 3)
    }

    private var iconColor: Color {
        switch item.type {
        case .folder:     return .blue
        case .pdf:        return .red
        case .note:       return .orange
        case .pap:        return .orange
        case .whiteboard: return .green
        case .mindmap:    return .purple
        }
    }
}
