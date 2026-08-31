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
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button { showMath = true } label: {
                            Label("Mathe", systemImage: "function")
                        }
                    }
                }
        } detail: {
            if let item = selectedItem {
                switch item.type {
                case .note:
                    InfiniteNotebookHostView(item: item)
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
        .sheet(isPresented: $showMath) {
            MathPanelView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
