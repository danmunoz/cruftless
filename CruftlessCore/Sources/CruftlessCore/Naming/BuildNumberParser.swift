import Foundation

/// Parses Apple OS build numbers (for example, `24A5418b`, `22G86`) to determine release characteristics.
public enum BuildNumberParser: Sendable {
    /// Determines whether an Apple build number represents a beta/seed build.
    public static func isBeta(_ buildNumber: String) -> Bool {
        let trimmed = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Lowercase suffix check (for example, 24A5418b ends with 'b').
        if let last = trimmed.last, last.isLetter, last.isLowercase {
            return true
        }

        // Numeric part check (for example, in 24A5418, find the digits after the letter 'A').
        if let letterIndex = trimmed.firstIndex(where: { $0.isLetter }) {
            let afterLetter = trimmed[trimmed.index(after: letterIndex)...]
            let digits = afterLetter.prefix(while: { $0.isNumber })
            if let seedNum = Int(digits), seedNum >= 5000 {
                return true
            }
        }

        return false
    }
}
