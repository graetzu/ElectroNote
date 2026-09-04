import SwiftUI

struct LiveCastBadgeButton: View {
    @ObservedObject private var liveCast = LiveCastServer.shared
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            if liveCast.isStreaming {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.red)
                    if liveCast.viewerCount > 0 {
                        Text("(\(liveCast.viewerCount))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.14))
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .clipShape(Capsule())
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .accessibilityLabel("Live-Übertragung")
        .sheet(isPresented: $showSheet) {
            LiveCastSheetView()
        }
    }
}
