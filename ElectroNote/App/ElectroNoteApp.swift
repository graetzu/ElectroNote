import SwiftUI

@main
struct ElectroNoteApp: App {
    @StateObject private var importManager = ExternalFileImportManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(importManager)
                .onOpenURL { url in
                    importManager.handleIncomingURL(url)
                }
        }
    }
}
