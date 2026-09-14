import SwiftUI

struct LiveCollabBadgeButton: View {
    let documentName: String
    let documentType: CollabDocumentType
    var initialTab: Int = 1

    @ObservedObject private var collab = LiveCollabSessionManager.shared
    @State private var showSheet: Bool = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            switch collab.sessionState {
            case .hosting, .connected:
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                    Text("\(collab.connectedPeers.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.14))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                )
                .clipShape(Capsule())

            case .idle, .error:
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Live")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
        .accessibilityLabel("Live-Zusammenarbeit")
        .sheet(isPresented: $showSheet) {
            LiveCollabSheetView(documentName: documentName, documentType: documentType, initialTab: initialTab)
        }
    }
}
