import Foundation

public enum TextChunker {
    /// Breaks on sentences, newlines, then word boundaries. A single extended
    /// grapheme is never split, even when it exceeds the requested size limit.
    public static func chunks(from pages: [PDFPageText], maxUTF16Length: Int = 700) -> [SpeechChunk] {
        let limit = max(1, maxUTF16Length)
        var result: [SpeechChunk] = []
        for page in pages {
            let text = page.text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            var start = text.startIndex
            while start < text.endIndex {
                while start < text.endIndex, text[start].isWhitespace {
                    start = text.index(after: start)
                }
                guard start < text.endIndex else { break }
                var cursor = start
                var length = 0
                var sentenceBoundary: String.Index?
                var wordBoundary: String.Index?

                while cursor < text.endIndex {
                    let character = text[cursor]
                    let next = text.index(after: cursor)
                    let width = String(character).utf16.count
                    if length + width > limit, cursor > start { break }
                    length += width
                    cursor = next
                    if character.isWhitespace { wordBoundary = next }
                    if character == "\n" || character == "\r" {
                        sentenceBoundary = next
                    } else if ".!?。！？".contains(character),
                              next == text.endIndex || text[next].isWhitespace {
                        sentenceBoundary = next
                    }
                    if length >= limit { break }
                }

                let end: String.Index
                if cursor == text.endIndex {
                    end = cursor
                } else {
                    end = sentenceBoundary ?? wordBoundary ?? cursor
                }
                let chunk = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    result.append(SpeechChunk(id: result.count, pageNumber: page.pageNumber, text: chunk))
                }
                start = end
            }
        }
        return result
    }
}
