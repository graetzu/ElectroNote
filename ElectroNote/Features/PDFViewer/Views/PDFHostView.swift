import SwiftUI

struct PDFHostView: View {
    @StateObject private var viewModel: PDFViewModel

    init(item: DocumentItem) {
        _viewModel = StateObject(wrappedValue: PDFViewModel(item: item))
    }

    var body: some View {
        Group {
            if let error = viewModel.loadError {
                ContentUnavailableView(error, systemImage: "doc.text.magnifyingglass")
            } else {
                PDFRepresentable(viewModel: viewModel)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { viewModel.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)

            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pageCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Button { viewModel.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
        }
    }
}
