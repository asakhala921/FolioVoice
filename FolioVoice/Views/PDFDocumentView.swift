import SwiftUI
import PDFKit

struct PDFDocumentView: UIViewRepresentable {
    let url: URL
    let pageNumber: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        context.coordinator.url = url
        updatePage(in: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.url != url {
            view.document = PDFDocument(url: url)
            context.coordinator.url = url
            context.coordinator.pageNumber = nil
        }
        updatePage(in: view, coordinator: context.coordinator)
    }

    private func updatePage(in view: PDFView, coordinator: Coordinator) {
        // Do not interrupt manual PDF scrolling on every spoken-word update.
        guard coordinator.pageNumber != pageNumber,
              let document = view.document,
              let page = document.page(at: max(0, min(pageNumber - 1, document.pageCount - 1))) else { return }
        coordinator.pageNumber = pageNumber
        view.go(to: page)
    }

    final class Coordinator {
        var url: URL?
        var pageNumber: Int?
    }
}
