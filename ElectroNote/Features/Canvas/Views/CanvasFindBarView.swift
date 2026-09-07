import SwiftUI

struct CanvasFindBarView: View {
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int // 0-based
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Magnifying glass icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            // Search text field
            TextField("In Notiz suchen…", text: $query)
                .focused($isFieldFocused)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
                .frame(minWidth: 160, maxWidth: 240)
                .onAppear {
                    isFieldFocused = true
                }

            if !query.isEmpty {
                // Clear button
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)

                // Match count indicator
                Text(matchCount > 0 ? "\(currentIndex + 1) von \(matchCount)" : "Keine Treffer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(matchCount > 0 ? .secondary : .red)
                    .padding(.horizontal, 4)

                // Previous match button
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .disabled(matchCount <= 1)
                .buttonStyle(.plain)

                // Next match button
                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                }
                .disabled(matchCount <= 1)
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 18)

            // Done / Close button
            Button(action: onClose) {
                Text("Fertig")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
