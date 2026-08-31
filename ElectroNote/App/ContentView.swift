import SwiftUI

struct ContentView: View {
    @StateObject private var browserVM = BrowserViewModel()
    @State private var selectedItem: DocumentItem?
    @State private var showMath = false

    var body: some View {
        NavigationSplitView {
            BrowserSidebarView(viewModel: browserVM, selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showMath = true
                        } label: {
                            Label("Mathe", systemImage: "function")
                        }
                    }
                }
        } detail: {
            if let item = selectedItem {
                switch item.type {
                case .note:
                    CanvasHostView(item: item)
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
        .sheet(isPresented: $showMath) {
            MathPanelView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
