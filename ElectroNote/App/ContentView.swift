import SwiftUI

struct ContentView: View {
    @StateObject private var browserVM = BrowserViewModel()
    @EnvironmentObject private var importManager: ExternalFileImportManager
    @ObservedObject private var collab = LiveCollabSessionManager.shared
    @State private var selectedItem: DocumentItem?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showMath = false

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            BrowserSidebarView(viewModel: browserVM, selectedItem: $selectedItem, sidebarVisibility: $sidebarVisibility)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            if let item = selectedItem {
                switch item.type {
                case .note:
                    InfiniteNotebookHostView(item: item)
                        .id(item.id)
                case .pap:
                    PAPDesignerView(item: item) { image in
                        // PAP used as standalone full-screen document; image export goes to photo library
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    .id(item.id)
                case .whiteboard:
                    WhiteboardView(item: item) { image in
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    .id(item.id)
                case .mindmap:
                    MindMapDesignerView(item: item) { image in
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    .id(item.id)
                case .pdf:
                    PDFHostView(item: item)
                        .id(item.id)
                case .folder:
                    WelcomeView()
                }
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // iPadOS stellt automatisch einen Sidebar-Toggle bereit —
        // kein eigener .toolbar-Modifier nötig (der crasht auf NavigationSplitView)
        .onChange(of: selectedItem) { _, newItem in
            if let item = newItem, !item.isFolder {
                #if !targetEnvironment(macCatalyst)
                withAnimation(.easeInOut(duration: 0.25)) {
                    sidebarVisibility = .detailOnly
                }
                #endif

                // If in an active live session, propagate document switch to other peers
                if let collabType = item.type.collabDocumentType,
                   (collab.sessionState == .hosting || collab.sessionState == .connected) {
                    let cleanName = LiveCollabSessionManager.cleanDocumentTitle(item.name)
                    if collab.activeDocumentTitle != cleanName || collab.activeDocumentType != collabType {
                        collab.switchDocument(title: cleanName, type: collabType)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .electroNoteDrawingBegan)) { _ in
            #if !targetEnvironment(macCatalyst)
            withAnimation { sidebarVisibility = .detailOnly }
            #endif
        }
        .onReceive(collab.$remoteDocumentSwitchRequest) { request in
            guard let request = request else { return }
            let targetDocType = request.type.browserDocumentType
            let cleanName = LiveCollabSessionManager.cleanDocumentTitle(request.title)
            print("[ContentView] Handling remoteDocumentSwitchRequest: '\(cleanName)' (\(request.type))")

            // Look up across all documents in library
            let allDocs = browserVM.listAllDocuments()
            let targetDoc: DocumentItem
            if let existing = allDocs.first(where: {
                $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame &&
                $0.type == targetDocType.itemType
            }) {
                targetDoc = existing
            } else if let newDoc = browserVM.createDocument(named: cleanName, type: targetDocType, at: browserVM.rootURL) {
                targetDoc = newDoc
            } else {
                print("[ContentView] Failed to find or create document '\(cleanName)'")
                return
            }

            if selectedItem?.path != targetDoc.path {
                print("[ContentView] Switching selectedItem to '\(targetDoc.name)'")
                selectedItem = targetDoc
            }

            #if !targetEnvironment(macCatalyst)
            withAnimation(.easeInOut(duration: 0.25)) {
                sidebarVisibility = .detailOnly
            }
            #endif
        }
        .sheet(isPresented: $showMath) {
            MathPanelView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $importManager.incomingFile) { file in
            IncomingFileImportSheet(
                file: file,
                browserVM: browserVM,
                selectedItem: $selectedItem,
                sidebarVisibility: $sidebarVisibility
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            importManager.handleIncomingURL(url)
            return true
        }
    }
}
