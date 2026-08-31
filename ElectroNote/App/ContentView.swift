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
                WelcomeView(selectedItemName: item.name)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
