import SwiftUI

struct WelcomeView: View {
    var selectedItemName: String? = nil

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
                Text("Wähle ein Dokument aus der Seitenleiste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
