import Foundation

enum TextChunker {
    static let maxChunkLength = 200

    static func chunk(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Split into sentences first
        var sentences: [String] = []
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..., options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            if let s = substring {
                sentences.append(s)
            }
        }

        // If enumeration produced nothing, treat whole text as one piece
        if sentences.isEmpty {
            sentences = [trimmed]
        }

        var chunks: [String] = []

        for sentence in sentences {
            if sentence.count <= maxChunkLength {
                chunks.append(sentence)
            } else {
                // Split long sentences at clause boundaries
                chunks.append(contentsOf: splitAtClauses(sentence))
            }
        }

        // Filter out empty/whitespace-only chunks, require at least 1 word
        return chunks.filter { chunk in
            let words = chunk.split(separator: " ")
            return !words.isEmpty
        }
    }

    private static func splitAtClauses(_ text: String) -> [String] {
        // Split at clause boundaries: comma followed by conjunction, semicolons
        let pattern = #"(?<=,\s)(?=and\s|but\s|or\s|so\s|yet\s)|(?<=;\s)|(?<=:\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else {
            return splitByLength(text)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else {
            return splitByLength(text)
        }

        var parts: [String] = []
        var lastIndex = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let part = String(text[lastIndex..<matchRange.lowerBound])
            if !part.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(part)
            }
            lastIndex = matchRange.lowerBound
        }

        // Add remaining text
        let remaining = String(text[lastIndex...])
        if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(remaining)
        }

        // If any parts are still too long, split by length
        var result: [String] = []
        for part in parts {
            if part.count <= maxChunkLength {
                result.append(part)
            } else {
                result.append(contentsOf: splitByLength(part))
            }
        }

        return result
    }

    private static func splitByLength(_ text: String) -> [String] {
        var chunks: [String] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            if remaining.count <= maxChunkLength {
                chunks.append(String(remaining))
                break
            }

            // Find the last space within the limit
            let endIndex =
                remaining.index(remaining.startIndex, offsetBy: maxChunkLength)
            let window = remaining[remaining.startIndex..<endIndex]

            if let lastSpace = window.lastIndex(of: " ") {
                let splitIndex = remaining.index(after: lastSpace)
                chunks.append(String(remaining[remaining.startIndex..<splitIndex]))
                remaining = remaining[splitIndex...]
            } else {
                // No space found, hard-split at limit
                chunks.append(String(remaining[remaining.startIndex..<endIndex]))
                remaining = remaining[endIndex...]
            }
        }

        return chunks
    }
}
