import SwiftUI

struct PDFHostView: View {
    @StateObject private var viewModel: PDFViewModel
    @StateObject private var clipArtVM: ClipArtViewModel
    @State private var showClipArtPicker = false

    init(item: DocumentItem) {
        let vm = PDFViewModel(item: item)
        _viewModel = StateObject(wrappedValue: vm)
        // Annotations folder is the sidecar directory for this PDF
        let annotationsURL = item.path.appendingPathExtension("annotations")
        try? FileManager.default.createDirectory(at: annotationsURL, withIntermediateDirectories: true)
        _clipArtVM = StateObject(wrappedValue: ClipArtViewModel(containerURL: annotationsURL, pageIndex: 0))
    }

    var body: some View {
        Group {
            if let error = viewModel.loadError {
                ContentUnavailableView(error, systemImage: "doc.text.magnifyingglass")
            } else {
                ZStack {
                    PDFRepresentable(viewModel: viewModel)
                    ClipArtOverlayView(viewModel: clipArtVM)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(viewModel.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: viewModel.currentPageIndex) { _, newPage in
            clipArtVM.switchToPage(newPage)
        }
        .onDisappear { clipArtVM.saveNow() }
        .sheet(isPresented: $showClipArtPicker) {
            ClipArtPickerView { entry in
                clipArtVM.insert(entry, at: CGPoint(x: 400, y: 300))
            }
        }
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

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Toggle(isOn: $viewModel.pencilOnly) {
                Image(systemName: viewModel.pencilOnly ? "pencil.and.scribble" : "hand.draw")
            }
            .accessibilityLabel(viewModel.pencilOnly ? "Nur Pencil (Zoom mit Fingern)" : "Finger & Pencil")
            .help(viewModel.pencilOnly ? "Nur Pencil (Zoom mit Fingern)" : "Finger & Pencil")

            Button { showClipArtPicker = true } label: {
                Image(systemName: "square.on.square.badge.person.crop")
            }
            .help("Symbol einfügen")
        }
    }
}
