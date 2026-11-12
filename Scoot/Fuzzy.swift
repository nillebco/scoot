import Foundation

/// Fuzzy matching for searchable palettes.
///
/// Deliberately free of AppKit and of the accessibility tree: this scores
/// strings and nothing else, so it can be unit-tested in isolation and reused
/// by every future mode (elements, menu items, commands, windows).
///
/// Semantics:
///
/// - The query is split on whitespace and *every* token must match (AND), the
///   same rule the pagecast browser extension uses.
/// - A token matches when its characters appear in order — a subsequence — so
///   `opte` finds "Open Terminal".
/// - Scoring rewards a match at the start of the string, at a word boundary and
///   inside a consecutive run, so `open` ranks "Open…" above "…reopen…".
enum Fuzzy {

    /// A successful match against one candidate.
    struct Match: Equatable {

        /// Higher is better. Only comparable between matches of the same query.
        let score: Double

        /// Offsets of the matched characters in the candidate, ascending.
        ///
        /// Use these to highlight. Offsets refer to the original candidate even
        /// though matching itself is case- and diacritic-insensitive.
        let indices: [Int]

        /// Consecutive runs of `indices`, ready to be turned into highlights.
        var ranges: [Range<Int>] {
            indices.reduce(into: [Range<Int>]()) { ranges, index in
                if let last = ranges.last, last.upperBound == index {
                    ranges[ranges.count - 1] = last.lowerBound..<(index + 1)
                } else {
                    ranges.append(index..<(index + 1))
                }
            }
        }
    }

    /// Scoring weights.
    ///
    /// Tuned so that a prefix match always beats a scattered one. Adjust only
    /// with tests in hand — see `ScootTests/FuzzyTests.swift`.
    enum Weight {
        static let character = 1.0
        static let consecutive = 2.0
        static let wordBoundary = 3.0
        static let startOfString = 5.0

        /// Charged per skipped character, so a tight match beats a sprawling one.
        static let gap = 0.05

        /// Gaps longer than this are charged as if they were this long: a single
        /// huge gap should not dominate the score.
        static let maxChargedGap = 10
    }

    // MARK: - Query

    /// Splits a query into its normalized tokens, dropping whitespace runs.
    ///
    /// An empty query yields no tokens, which matches every candidate with a
    /// score of zero (see `match(query:candidate:)`).
    static func tokens(of query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Matching

    /// Scores one candidate against a query. Returns nil as soon as one token
    /// fails to match, which is what gives the AND semantics.
    static func match(query: String, candidate: String) -> Match? {
        let prepared = Prepared(candidate)

        var score = 0.0
        var indices = [Int]()

        for token in tokens(of: query) {
            guard let result = match(token: Array(token), in: prepared) else {
                return nil
            }
            score += result.score
            indices.append(contentsOf: result.indices)
        }

        return Match(score: score, indices: indices.sorted())
    }

    /// Filters and ranks candidates, best match first.
    ///
    /// Ties are broken by the shortest candidate text, then alphabetically, so
    /// an exact short match ("Open") ranks above a longer one ("Open in New
    /// Tab") with the same score.
    static func rank<Element>(
        _ candidates: [Element],
        query: String,
        text: (Element) -> String
    ) -> [(element: Element, match: Match)] {

        let scored = candidates.compactMap { element -> (element: Element, match: Match, text: String)? in
            let text = text(element)
            guard let match = match(query: query, candidate: text) else {
                return nil
            }
            return (element: element, match: match, text: text)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.match.score != rhs.match.score {
                    return lhs.match.score > rhs.match.score
                }
                if lhs.text.count != rhs.text.count {
                    return lhs.text.count < rhs.text.count
                }
                return lhs.text.localizedStandardCompare(rhs.text) == .orderedAscending
            }
            .map { (element: $0.element, match: $0.match) }
    }

    // MARK: - Internals

    /// A candidate string with its folding precomputed, so ranking a long list
    /// does not fold the same characters over and over.
    private struct Prepared {

        let characters: [Character]

        /// Lowercased and diacritic-folded, index-aligned with `characters`.
        let folded: [Character]

        init(_ value: String) {
            self.characters = Array(value)
            self.folded = self.characters.map(Fuzzy.folded)
        }
    }

    private static func match(
        token: [Character],
        in candidate: Prepared
    ) -> (score: Double, indices: [Int])? {

        let needle = token.map(folded)

        guard !needle.isEmpty else {
            return (0.0, [])
        }

        var score = 0.0
        var indices = [Int]()
        var position = 0

        for index in candidate.folded.indices {
            guard position < needle.count else {
                break
            }
            guard candidate.folded[index] == needle[position] else {
                continue
            }

            var points = Weight.character

            if index == 0 {
                points += Weight.startOfString
            } else if isWordBoundary(candidate.characters, at: index) {
                points += Weight.wordBoundary
            }

            if let previous = indices.last {
                let gap = index - previous - 1
                if gap == 0 {
                    points += Weight.consecutive
                } else {
                    points -= Weight.gap * Double(min(gap, Weight.maxChargedGap))
                }
            }

            score += points
            indices.append(index)
            position += 1
        }

        guard position == needle.count else {
            return nil
        }

        return (score, indices)
    }

    /// True when `index` starts a new word: after a separator, or at a
    /// camelCase/PascalCase hump.
    private static func isWordBoundary(_ characters: [Character], at index: Int) -> Bool {
        let current = characters[index]
        let previous = characters[index - 1]

        if previous.isWhitespace || "-_./:(".contains(previous) {
            return true
        }

        return current.isUppercase && previous.isLowercase
    }

    /// Folds one character to a single lowercase, accent-free character.
    ///
    /// Characters whose folding is not one-to-one (rare: "ß", "İ") are left
    /// alone, keeping the array index-aligned with the original string.
    private static func folded(_ character: Character) -> Character {
        let folded = String(character).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        return folded.count == 1 ? (folded.first ?? character) : character
    }

}
