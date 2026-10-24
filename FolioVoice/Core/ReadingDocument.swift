import Foundation

public struct PDFPageText: Codable, Equatable, Sendable, Identifiable {
    public let pageNumber: Int
    public let text: String
    public var id: Int { pageNumber }

    public init(pageNumber: Int, text: String) {
        self.pageNumber = pageNumber
        self.text = text
    }
}

public struct SpeechChunk: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let pageNumber: Int
    public let text: String

    public init(id: Int, pageNumber: Int, text: String) {
        self.id = id
        self.pageNumber = pageNumber
        self.text = text
    }
}

public struct ReadingDocument: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let filename: String
    public let importedAt: Date
    /// The physical PDF page count, including pages without readable text.
    public let pageCount: Int
    public let pages: [PDFPageText]
    public var chunkIndex: Int
    /// UTF-16 offset in the current chunk, matching AVSpeechSynthesizer ranges.
    public var utf16Offset: Int
    public var isFinished: Bool

    public var chunks: [SpeechChunk] { TextChunker.chunks(from: pages) }

    public init(
        id: UUID = UUID(),
        title: String,
        filename: String,
        importedAt: Date = Date(),
        pageCount: Int,
        pages: [PDFPageText],
        chunkIndex: Int = 0,
        utf16Offset: Int = 0,
        isFinished: Bool = false
    ) {
        self.id = id
        self.title = title
        self.filename = filename
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.pages = pages
        self.chunkIndex = chunkIndex
        self.utf16Offset = utf16Offset
        self.isFinished = isFinished
    }
}
