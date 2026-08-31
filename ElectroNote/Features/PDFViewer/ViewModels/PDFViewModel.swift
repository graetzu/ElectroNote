import PDFKit

@MainActor
final class PDFViewModel: ObservableObject {
    @Published var currentPageIndex: Int = 0
    @Published var hasUnsavedAnnotations: Bool = false

    let item: DocumentItem
    let document: PDFDocument?
    let annotationStore: PDFAnnotationStore?

    var loadError: String? { document == nil ? "PDF konnte nicht geöffnet werden." : nil }
    var pageCount: Int { document?.pageCount ?? 0 }
    var canGoBack: Bool    { currentPageIndex > 0 }
    var canGoForward: Bool { currentPageIndex < pageCount - 1 }

    init(item: DocumentItem) {
        self.item = item
        if let doc = PDFDocument(url: item.path) {
            document = doc
            annotationStore = PDFAnnotationStore(pdfURL: item.path)
        } else {
            document = nil
            annotationStore = nil
        }
    }

    func goBack()    { if canGoBack    { currentPageIndex -= 1 } }
    func goForward() { if canGoForward { currentPageIndex += 1 } }
}
