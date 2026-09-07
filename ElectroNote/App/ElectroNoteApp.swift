import SwiftUI

@main
struct ElectroNoteApp: App {
    @StateObject private var importManager = ExternalFileImportManager.shared

    init() {
        // Kick off background indexing for notes (zero-lag background sweep)
        NoteIndexingService.shared.startIndexingAllDocuments(fileService: FileService())
    }

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
