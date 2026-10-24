import Foundation
import PDFKit
import Vision
import CoreGraphics

public enum DocumentError: LocalizedError {
    case fileTooLarge
    case tooManyPages
    case textTooLarge
    case invalidPDF
    case passwordProtected
    case noReadableText
    case unreadablePage(Int)
    case ocrFailed(Int)
    case libraryUnreadable
    case unsafeFilename

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "This PDF is larger than 100 MB. Please import a smaller file."
        case .tooManyPages:
            return "This PDF has more than 1,000 pages. Please split it into smaller PDFs."
        case .textTooLarge:
            return "This PDF contains too much text to read in one session. Please split it into smaller PDFs."
        case .invalidPDF:
            return "This file could not be opened as a PDF. It may be damaged or empty."
        case .passwordProtected:
            return "This PDF needs a password. Please unlock it and save an unprotected copy first."
        case .noReadableText:
            return "No readable text was found, including after scanning the pages. Try a clearer PDF."
        case .unreadablePage(let number):
            return "Page \(number) could not be read. Please export a new copy of this PDF."
        case .ocrFailed(let number):
            return "Text recognition failed on page \(number). Please try importing the PDF again."
        case .libraryUnreadable:
            return "Your saved library could not be read. Your PDFs have been kept intact. Restore the app's data from a backup before adding or removing documents."
        case .unsafeFilename:
            return "A document has an invalid local filename. Its files have been kept intact."
        }
    }
}

public actor DocumentRepository {
    private struct Manifest: Codable {
        let version: Int
        let documents: [ReadingDocument]
    }

    private let directory: URL
    private let manifestURL: URL
    private static let maximumFileSize: Int64 = 100 * 1_024 * 1_024
    private static let maximumPages = 1_000
    private static let maximumTextLength = 10_000_000

    public init(directory: URL? = nil) throws {
        let destination: URL
        if let directory {
            destination = directory
        } else {
            destination = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("FolioVoice", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        self.directory = destination
        self.manifestURL = destination.appendingPathComponent("library.json")
    }

    public func load() throws -> [ReadingDocument] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.version == 1,
                  Set(manifest.documents.map(\.id)).count == manifest.documents.count,
                  manifest.documents.allSatisfy({ Self.isSafeFilename($0.filename) }) else {
                throw DocumentError.libraryUnreadable
            }
            return manifest.documents
        } catch {
            throw DocumentError.libraryUnreadable
        }
    }

    public func save(_ documents: [ReadingDocument]) throws {
        // Do not turn an unreadable library into a new empty one by accident.
        if FileManager.default.fileExists(atPath: manifestURL.path) { _ = try load() }
        guard documents.allSatisfy({ Self.isSafeFilename($0.filename) }) else {
            throw DocumentError.unsafeFilename
        }
        guard Set(documents.map(\.id)).count == documents.count else {
            throw DocumentError.libraryUnreadable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest(version: 1, documents: documents)).write(to: manifestURL, options: .atomic)
    }

    public func fileURL(for document: ReadingDocument) -> URL {
        // Strip any path components even for models constructed outside this repository.
        directory.appendingPathComponent((document.filename as NSString).lastPathComponent)
    }

    public func removeFile(for document: ReadingDocument) throws {
        guard Self.isSafeFilename(document.filename) else { throw DocumentError.unsafeFilename }
        let url = fileURL(for: document)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public nonisolated func importPDF(
        from url: URL,
        onProgress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> ReadingDocument {
        try Task.checkCancellation()
        let id = UUID()
        let filename = "\(id.uuidString).pdf"
        let localURL = directory.appendingPathComponent(filename)
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: localURL) }
        }
        try Self.copyCoordinatedPDF(from: url, to: localURL)
        try Task.checkCancellation()
        guard let pdf = PDFDocument(url: localURL) else { throw DocumentError.invalidPDF }
        guard !pdf.isLocked else { throw DocumentError.passwordProtected }
        let count = pdf.pageCount
        guard count > 0 else { throw DocumentError.invalidPDF }
        guard count <= Self.maximumPages else { throw DocumentError.tooManyPages }
        onProgress(0, count)

        var pages: [PDFPageText] = []
        var textLength = 0
        for index in 0..<count {
            try Task.checkCancellation()
            let text: String = try autoreleasepool {
                guard let page = pdf.page(at: index) else {
                    throw DocumentError.unreadablePage(index + 1)
                }
                let embedded = Self.cleanText(page.string ?? "")
                if !embedded.isEmpty { return embedded }
                return try Self.recognizeText(in: page, pageNumber: index + 1)
            }
            try Task.checkCancellation()
            textLength += text.utf16.count
            guard textLength <= Self.maximumTextLength else { throw DocumentError.textTooLarge }
            // Keep empty pages so physical page numbering stays accurate.
            pages.append(PDFPageText(pageNumber: index + 1, text: text))
            onProgress(index + 1, count)
        }
        guard pages.contains(where: { !$0.text.isEmpty }) else { throw DocumentError.noReadableText }
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        completed = true
        return ReadingDocument(
            id: id, title: title.isEmpty ? "Untitled PDF" : title,
            filename: filename, pageCount: count, pages: pages
        )
    }

    private static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name == (name as NSString).lastPathComponent
            && !name.contains("\\") && (name as NSString).pathExtension.lowercased() == "pdf"
    }

    private static func copyCoordinatedPDF(from source: URL, to destination: URL) throws {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: coordinatedURL.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw DocumentError.invalidPDF
                }
                guard size <= maximumFileSize else { throw DocumentError.fileTooLarge }
                try FileManager.default.copyItem(at: coordinatedURL, to: destination)
                let copied = try FileManager.default.attributesOfItem(atPath: destination.path)
                if ((copied[.size] as? NSNumber)?.int64Value ?? 0) > maximumFileSize {
                    throw DocumentError.fileTooLarge
                }
            } catch { copyError = error }
        }
        if let error = copyError { throw error }
        if let error = coordinationError { throw error }
    }

    private static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func recognizeText(in page: PDFPage, pageNumber: Int) throws -> String {
        try Task.checkCancellation()
        guard let pageRef = page.pageRef else { throw DocumentError.unreadablePage(pageNumber) }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
              (0.01...1_000_000).contains(bounds.width),
              (0.01...1_000_000).contains(bounds.height) else {
            throw DocumentError.unreadablePage(pageNumber)
        }
        // Bound both pixel count and edge length; scanned books never create
        // page-sized, print-resolution image buffers in memory.
        let pixelScale = min(1_800 / max(bounds.width, bounds.height),
                             sqrt(2_000_000 / (bounds.width * bounds.height)))
        let width = max(1, Int(ceil(bounds.width * pixelScale)))
        let height = max(1, Int(ceil(bounds.height * pixelScale)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw DocumentError.ocrFailed(pageNumber) }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(target)
        context.concatenate(pageRef.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pageRef)
        guard let image = context.makeImage() else { throw DocumentError.ocrFailed(pageNumber) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DocumentError.ocrFailed(pageNumber)
        }
        return cleanText((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
    }
}
