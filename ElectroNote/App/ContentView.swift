import SwiftUI

struct ContentView: View {
    @StateObject private var browserVM = BrowserViewModel()
    @State private var selectedItem: DocumentItem?

    var body: some View {
        NavigationSplitView {
            BrowserSidebarView(viewModel: browserVM, selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            if let item = selectedItem {
                switch item.type {
                case .note:
                    CanvasHostView(item: item)
                        .id(item.id)        // rebuild when switching notes
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
    }
}
