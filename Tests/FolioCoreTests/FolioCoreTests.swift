import XCTest
import Foundation
import CoreGraphics
import CoreText
@testable import FolioCore

final class TextChunkerTests: XCTestCase {
    func testSentenceBoundariesAndPhysicalPageNumbers() {
        let pages = [
            PDFPageText(pageNumber: 1, text: "One sentence. Another longer sentence goes here."),
            PDFPageText(pageNumber: 2, text: "   \n"),
            PDFPageText(pageNumber: 3, text: "Last page.")
        ]
        let chunks = TextChunker.chunks(from: pages, maxUTF16Length: 32)
        XCTAssertEqual(chunks.first?.text, "One sentence.")
        XCTAssertEqual(chunks.last?.pageNumber, 3)
        XCTAssertEqual(chunks.map(\.id), Array(0..<chunks.count))
        XCTAssertFalse(chunks.contains(where: { $0.pageNumber == 2 }))
        XCTAssertTrue(chunks.allSatisfy { $0.text.utf16.count <= 32 })
        XCTAssertEqual(chunks.filter { $0.pageNumber == 1 }.map(\.text).joined(separator: " "), pages[0].text)
    }

    func testUnicodeGraphemesAreNeverSplitOrLost() {
        let original = "👩🏽‍🚀👨‍👩‍👧‍👦e\u{301}🇮🇳你好世界"
        let chunks = TextChunker.chunks(from: [PDFPageText(pageNumber: 1, text: original)], maxUTF16Length: 3)
        XCTAssertEqual(chunks.map(\.text).joined(), original)
        XCTAssertEqual(chunks.flatMap { Array($0.text) }, Array(original))
        XCTAssertTrue(chunks.allSatisfy { !$0.text.contains("�") })
    }

    func testNewlinesAndLongWordsTerminateWithZeroLimit() {
        let newlineChunks = TextChunker.chunks(
            from: [PDFPageText(pageNumber: 1, text: "First line\r\nSecond longer line")],
            maxUTF16Length: 18
        )
        XCTAssertEqual(newlineChunks.first?.text, "First line")
        let tiny = TextChunker.chunks(from: [PDFPageText(pageNumber: 4, text: "abc")], maxUTF16Length: 0)
        XCTAssertEqual(tiny.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(TextChunker.chunks(from: []), [])
    }
}

final class DocumentRepositoryTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }

    func testPersistenceRoundTripPreservesResumePosition() async throws {
        let repository = try DocumentRepository(directory: temporary.appendingPathComponent("library"))
        let empty = try await repository.load()
        XCTAssertEqual(empty, [])
        let document = ReadingDocument(
            title: "A book", filename: "book.pdf", pageCount: 3,
            pages: [PDFPageText(pageNumber: 1, text: "A sample."), PDFPageText(pageNumber: 3, text: "More text.")],
            chunkIndex: 1, utf16Offset: 5, isFinished: false
        )
        try await repository.save([document])
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded, [document])
        XCTAssertEqual(reloaded.first?.chunks.last?.pageNumber, 3)
    }

    func testCorruptManifestCannotBeOverwritten() async throws {
        let repository = try DocumentRepository(directory: temporary)
        let manifest = temporary.appendingPathComponent("library.json")
        let broken = Data("{this is not valid JSON".utf8)
        try broken.write(to: manifest)
        do {
            _ = try await repository.load()
            XCTFail("A corrupt library must fail to load.")
        } catch { XCTAssertTrue(error is DocumentError) }
        do {
            try await repository.save([])
            XCTFail("Saving must not destroy a corrupt library.")
        } catch { XCTAssertTrue(error is DocumentError) }
        XCTAssertEqual(try Data(contentsOf: manifest), broken)
    }

    func testDeleteOnlyRemovesSelectedLocalCopyAndIsIdempotent() async throws {
        let repository = try DocumentRepository(directory: temporary)
        let selected = ReadingDocument(title: "Selected", filename: "selected.pdf", pageCount: 1, pages: [])
        let kept = temporary.appendingPathComponent("kept.pdf")
        try Data("keep".utf8).write(to: kept)
        let selectedURL = await repository.fileURL(for: selected)
        try Data("remove".utf8).write(to: selectedURL)
        try await repository.removeFile(for: selected)
        try await repository.removeFile(for: selected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))

        let unsafe = ReadingDocument(title: "Unsafe", filename: "../outside.pdf", pageCount: 1, pages: [])
        do {
            try await repository.removeFile(for: unsafe)
            XCTFail("Paths outside the repository must not be accepted.")
        } catch { XCTAssertTrue(error is DocumentError) }
    }

    func testImportsRealTextPDFAndKeepsOriginal() async throws {
        let source = temporary.appendingPathComponent("A short book.pdf")
        try makePDF(at: source, pages: ["Hello from page one.", "The second page is here."])
        let repository = try DocumentRepository(directory: temporary.appendingPathComponent("library"))
        let progress = ProgressRecorder()
        let document = try await repository.importPDF(from: source) { progress.record($0, $1) }
        XCTAssertEqual(document.title, "A short book")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.pages.map(\.pageNumber), [1, 2])
        XCTAssertTrue(document.pages[0].text.contains("Hello from page one."))
        XCTAssertTrue(document.pages[1].text.contains("The second page is here."))
        XCTAssertEqual(progress.values.map { $0.0 }, [0, 1, 2])
        XCTAssertTrue(progress.values.allSatisfy { $0.1 == 2 })
        let local = await repository.fileURL(for: document)
        XCTAssertNotEqual(local, source)
        XCTAssertEqual(try Data(contentsOf: local), try Data(contentsOf: source))
        try await repository.removeFile(for: document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testImageOnlyPDFUsesOCRAndPreservesBlankPages() async throws {
        let source = temporary.appendingPathComponent("Scanned.pdf")
        try makePDF(at: source, pages: ["A clear scanned page.", ""], rasterized: true)
        let repository = try DocumentRepository(directory: temporary.appendingPathComponent("library"))
        let document = try await repository.importPDF(from: source) { _, _ in }
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.pages.count, 2)
        XCTAssertTrue(document.pages[0].text.lowercased().contains("clear scanned page"), document.pages[0].text)
        XCTAssertEqual(document.pages[1].text, "")
        XCTAssertTrue(document.chunks.allSatisfy { $0.pageNumber == 1 })
    }

    func testFailedImportCleansUpLocalCopy() async throws {
        let source = temporary.appendingPathComponent("Broken.pdf")
        try Data("This is not a PDF".utf8).write(to: source)
        let library = temporary.appendingPathComponent("library")
        let repository = try DocumentRepository(directory: library)
        do {
            _ = try await repository.importPDF(from: source) { _, _ in }
            XCTFail("An invalid PDF should fail.")
        } catch { XCTAssertTrue(error is DocumentError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testOversizedPDFRejectedBeforeCopy() async throws {
        let source = temporary.appendingPathComponent("Oversized.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 100 * 1_024 * 1_024 + 1)
        try handle.close()
        let library = temporary.appendingPathComponent("library")
        let repository = try DocumentRepository(directory: library)
        do {
            _ = try await repository.importPDF(from: source) { _, _ in }
            XCTFail("Oversized files must be rejected.")
        } catch DocumentError.fileTooLarge { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
    }

    func testAlreadyCancelledImportDoesNotCreateCopy() async throws {
        let source = temporary.appendingPathComponent("Cancel.pdf")
        try makePDF(at: source, pages: ["Some text."])
        let library = temporary.appendingPathComponent("library")
        let repository = try DocumentRepository(directory: library)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.importPDF(from: source) { _, _ in }
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled import must stop.")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
    }

    private func makePDF(at url: URL, pages: [String], rasterized: Bool = false) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for text in pages {
            context.beginPDFPage(nil)
            if rasterized {
                let bitmap = try XCTUnwrap(CGContext(
                    data: nil, width: 1224, height: 1584, bitsPerComponent: 8,
                    bytesPerRow: 1224 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                bitmap.scaleBy(x: 2, y: 2)
                draw(text, in: bitmap, bounds: mediaBox)
                context.draw(try XCTUnwrap(bitmap.makeImage()), in: mediaBox)
            } else {
                draw(text, in: context, bounds: mediaBox)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func draw(_ text: String, in context: CGContext, bounds: CGRect) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 28, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        context.textPosition = CGPoint(x: 48, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(Int, Int)] = []
    var values: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func record(_ current: Int, _ total: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage.append((current, total))
    }
}
