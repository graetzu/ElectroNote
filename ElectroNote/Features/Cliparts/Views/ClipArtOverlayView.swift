import SwiftUI

// Transparent overlay that renders placed cliparts.
// Empty areas pass through to PencilKit canvas / PDF below.
struct ClipArtOverlayView: View {
    @ObservedObject var viewModel: ClipArtViewModel

    var body: some View {
        ZStack {
            ForEach(viewModel.items) { item in
                PlacedClipArtView(
                    item: item,
                    isSelected: viewModel.selectedID == item.id,
                    onTap:      { viewModel.select(item) },
                    onMoveBy:   { viewModel.move(item: item, by: $0) },
                    onMoveEnd:  { viewModel.commitMove() },
                    onDelete:   { viewModel.delete(item) }
                )
                .position(x: item.x, y: item.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tap on empty area → deselect
        .simultaneousGesture(TapGesture().onEnded { viewModel.deselect() })
    }
}

// MARK: - Single placed item

private struct PlacedClipArtView: View {
    let item: ClipArtItem
    let isSelected: Bool
    let onTap:     () -> Void
    let onMoveBy:  (CGSize) -> Void
    let onMoveEnd: () -> Void
    let onDelete:  () -> Void

    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        Image(systemName: item.symbolName)
            .font(.system(size: item.size, weight: .regular))
            .foregroundStyle(item.colorKey.color)
            .padding(10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                    }
                    .offset(x: 14, y: -14)
                }
            }
            .offset(dragOffset)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        onMoveBy(value.translation)
                        onMoveEnd()
                    }
            )
    }
}
