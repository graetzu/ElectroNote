import SwiftUI

struct ContentView: View {
    @StateObject private var browserVM = BrowserViewModel()
    @State private var selectedItem: DocumentItem?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showMath = false

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            BrowserSidebarView(viewModel: browserVM, selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            if let item = selectedItem {
                switch item.type {
                case .note:
                    InfiniteNotebookHostView(item: item)
                        .id(item.id)
                case .pap:
                    PAPDesignerView { image in
                        // PAP used as standalone full-screen document; image export goes to photo library
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    .id(item.id)
                case .whiteboard:
                    WhiteboardView { image in
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    .id(item.id)
                case .mindmap:
                    MindMapDesignerView { image in
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
        .onReceive(NotificationCenter.default.publisher(for: .electroNoteDrawingBegan)) { _ in
            withAnimation { sidebarVisibility = .detailOnly }
        }
        .sheet(isPresented: $showMath) {
            MathPanelView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
