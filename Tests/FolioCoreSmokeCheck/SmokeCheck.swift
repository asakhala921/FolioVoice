// A dependency-free verification runner for Macs with Command Line Tools but
// without Xcode's XCTest framework. Run: swift run FolioCoreSmokeCheck
import Foundation
import CoreGraphics
import CoreText
import FolioCore

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationFailure(description: message) }
}

func draw(_ text: String, in context: CGContext, bounds: CGRect) {
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(bounds)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 28, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
    ]
    context.textPosition = CGPoint(x: 48, y: 700)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
}

func makePDF(at url: URL, pages: [String], rasterized: Bool = false) throws {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        throw VerificationFailure(description: "Could not generate PDF fixture")
    }
    for text in pages {
        context.beginPDFPage(nil)
        if rasterized {
            guard let bitmap = CGContext(
                data: nil, width: 1224, height: 1584, bitsPerComponent: 8,
                bytesPerRow: 1224 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw VerificationFailure(description: "Could not generate scanned fixture") }
            bitmap.scaleBy(x: 2, y: 2)
            draw(text, in: bitmap, bounds: box)
            guard let image = bitmap.makeImage() else {
                throw VerificationFailure(description: "Could not render scanned fixture")
            }
            context.draw(image, in: box)
        } else { draw(text, in: context, bounds: box) }
        context.endPDFPage()
    }
    context.closePDF()
}

@main struct SmokeCheck {
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FolioCore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var checks = 0

        let original = "👩🏽‍🚀👨‍👩‍👧‍👦e\u{301}🇮🇳你好世界"
        let unicode = TextChunker.chunks(from: [PDFPageText(pageNumber: 1, text: original)], maxUTF16Length: 3)
        try require(unicode.map(\.text).joined() == original, "Unicode content must survive chunking")
        try require(unicode.flatMap { Array($0.text) } == Array(original), "Graphemes must remain intact")
        checks += 2
        let sentences = TextChunker.chunks(from: [PDFPageText(pageNumber: 3, text: "One sentence. Another longer sentence goes here.")], maxUTF16Length: 32)
        try require(sentences.first?.text == "One sentence.", "Prefer sentence boundaries")
        try require(sentences.allSatisfy { $0.text.utf16.count <= 32 && $0.pageNumber == 3 }, "Respect chunk size and physical page number")
        checks += 2

        let library = temporary.appendingPathComponent("library")
        let repository = try DocumentRepository(directory: library)
        let source = temporary.appendingPathComponent("A short book.pdf")
        try makePDF(at: source, pages: ["Hello from page one.", "The second page is here."])
        var document = try await repository.importPDF(from: source) { _, _ in }
        try require(document.title == "A short book" && document.pageCount == 2, "Retain title and page count")
        try require(document.pages[0].text.contains("Hello from page one."), "Extract real embedded text")
        try require(document.pages[1].text.contains("The second page is here."), "Extract subsequent pages")
        let copiedURL = await repository.fileURL(for: document)
        let copiedData = try Data(contentsOf: copiedURL)
        let sourceData = try Data(contentsOf: source)
        try require(copiedData == sourceData && copiedURL != source, "Copy PDF without modifying source")
        checks += 4

        document.chunkIndex = 1
        document.utf16Offset = 4
        try await repository.save([document])
        let loaded = try await repository.load()
        try require(loaded == [document], "Persist title, text, metadata and resume position")
        checks += 1
        do {
            try await repository.save([document, document])
            throw VerificationFailure(description: "Reject duplicate document IDs")
        } catch is DocumentError { checks += 1 }

        let scanned = temporary.appendingPathComponent("Scanned.pdf")
        try makePDF(at: scanned, pages: ["A clear scanned page.", ""], rasterized: true)
        let scan = try await repository.importPDF(from: scanned) { _, _ in }
        try require(scan.pages[0].text.lowercased().contains("clear scanned page"), "OCR image-only text: \(scan.pages[0].text)")
        try require(scan.pageCount == 2 && scan.pages[1].text.isEmpty, "Preserve physical blank pages")
        try require(scan.chunks.allSatisfy { $0.pageNumber == 1 }, "Do not speak blank pages")
        checks += 3

        try await repository.removeFile(for: document)
        try await repository.removeFile(for: document)
        try require(!FileManager.default.fileExists(atPath: copiedURL.path), "Delete local copy idempotently")
        try require(FileManager.default.fileExists(atPath: source.path), "Keep original PDF after delete")
        checks += 2

        let broken = temporary.appendingPathComponent("Broken.pdf")
        try Data("invalid PDF".utf8).write(to: broken)
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: library.path))
        do {
            _ = try await repository.importPDF(from: broken) { _, _ in }
            throw VerificationFailure(description: "Reject invalid PDF")
        } catch is DocumentError { checks += 1 }
        let after = try Set(FileManager.default.contentsOfDirectory(atPath: library.path))
        try require(before == after, "Clean local copy after a failed import")
        checks += 1

        let blank = temporary.appendingPathComponent("Blank.pdf")
        try makePDF(at: blank, pages: [""])
        do {
            _ = try await repository.importPDF(from: blank) { _, _ in }
            throw VerificationFailure(description: "Reject documents with no readable text")
        } catch DocumentError.noReadableText { checks += 1 }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.importPDF(from: source) { _, _ in }
        }
        do {
            _ = try await cancelled.value
            throw VerificationFailure(description: "Respect task cancellation")
        } catch is CancellationError { checks += 1 }

        let manifestURL = library.appendingPathComponent("library.json")
        let corrupt = Data("{bad JSON".utf8)
        try corrupt.write(to: manifestURL)
        do {
            _ = try await repository.load()
            throw VerificationFailure(description: "Reject corrupt manifests")
        } catch DocumentError.libraryUnreadable { checks += 1 }
        do {
            try await repository.save([])
            throw VerificationFailure(description: "Prevent overwriting corrupt manifests")
        } catch DocumentError.libraryUnreadable { checks += 1 }
        let preserved = try Data(contentsOf: manifestURL)
        try require(preserved == corrupt, "Keep corrupt manifest intact for recovery")
        checks += 1
        print("PASS: \(checks) core checks, including generated text PDFs, scanned-PDF OCR, persistence, deletion, corruption protection and cancellation.")
    }
}
