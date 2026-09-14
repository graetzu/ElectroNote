import SwiftUI

struct WelcomeView: View {
    var selectedItemName: String? = nil
    @State private var showCollabSheet = false
    @State private var collabInitialTab = 1

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

                HStack(spacing: 16) {
                    Button {
                        collabInitialTab = 1
                        showCollabSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                            Text("Sitzung beitreten")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: .blue.opacity(0.3), radius: 6, y: 3)
                    }

                    Button {
                        collabInitialTab = 0
                        showCollabSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.wave.2.fill")
                                .font(.title3)
                            Text("Sitzung hosten")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.3), radius: 6, y: 3)
                    }
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showCollabSheet) {
            LiveCollabSheetView(documentName: "Live-Zusammenarbeit", documentType: .note, initialTab: collabInitialTab)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
