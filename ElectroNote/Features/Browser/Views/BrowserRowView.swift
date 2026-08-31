import SwiftUI

struct BrowserRowView: View {
    let item: DocumentItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 36, height: 36)
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
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
        case .folder: return .blue
        case .pdf:    return .red
        case .note:   return .orange
        }
    }
}
