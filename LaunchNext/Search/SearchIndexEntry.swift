import Foundation

struct SearchIndexEntry {
    let displayName: String
    let normalizedName: String
    let tokens: [String]
    let acronym: String

    init(displayName: String) {
        self.displayName = displayName
        self.normalizedName = Self.normalize(displayName)
        self.tokens = Self.tokenize(displayName)
        self.acronym = tokens.compactMap(\.first).map(String.init).joined()
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined()
    }

    static func tokenize(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}
