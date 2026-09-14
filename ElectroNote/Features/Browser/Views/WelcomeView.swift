import SwiftUI

struct WelcomeView: View {
    var selectedItemName: String? = nil
    @State private var showCollabSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            if let name = selectedItemName {
                Text(name)
                    .font(.title2.bold())
                Text("Viewer für diesen Dateityp folgt in der nächsten Phase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("ElectroNote")
                    .font(.largeTitle.bold())
                Text("Wähle ein Dokument aus der Seitenleiste oder starte eine Live-Sitzung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    showCollabSheet = true
                } label: {
                    Label("Live-Sitzung beitreten / starten", systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.3), radius: 6, y: 3)
                }
                .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showCollabSheet) {
            LiveCollabSheetView(documentName: "Live-Zusammenarbeit", documentType: .note)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
