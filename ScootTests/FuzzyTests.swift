import XCTest

class FuzzyTests: XCTestCase {

    // MARK: - Matching

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertNil(Fuzzy.match(query: "xyz", candidate: "Open Terminal"))
        XCTAssertNil(Fuzzy.match(query: "opne", candidate: "Open"))
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(Fuzzy.match(query: "ot", candidate: "Open Terminal"))
        XCTAssertNotNil(Fuzzy.match(query: "opte", candidate: "Open Terminal"))
    }

    func testEmptyQueryMatchesEverythingWithZeroScore() {
        let match = Fuzzy.match(query: "", candidate: "Anything at all")

        XCTAssertEqual(match?.score, 0.0)
        XCTAssertEqual(match?.indices, [])
    }

    func testWhitespaceOnlyQueryMatchesEverything() {
        XCTAssertEqual(Fuzzy.match(query: "   \t ", candidate: "Anything")?.score, 0.0)
    }

    func testTokensAreAnded() {
        XCTAssertNotNil(Fuzzy.match(query: "op term", candidate: "Open Terminal"))

        // "zz" is not present, so the whole match fails even though "op" is.
        XCTAssertNil(Fuzzy.match(query: "op zz", candidate: "Open Terminal"))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertNotNil(Fuzzy.match(query: "OPEN", candidate: "open"))
        XCTAssertNotNil(Fuzzy.match(query: "open", candidate: "OPEN"))
    }

    func testMatchingIsDiacriticInsensitive() {
        XCTAssertNotNil(Fuzzy.match(query: "resume", candidate: "Résumé"))
        XCTAssertNotNil(Fuzzy.match(query: "resume", candidate: "RESUME"))
    }

    // MARK: - Scoring

    func testStartOfStringRanksAboveMidString() throws {
        let prefix = try XCTUnwrap(Fuzzy.match(query: "open", candidate: "Open"))
        let infix = try XCTUnwrap(Fuzzy.match(query: "open", candidate: "Reopen"))

        XCTAssertGreaterThan(prefix.score, infix.score)
    }

    func testWordBoundaryRanksAboveMidWord() throws {
        let boundary = try XCTUnwrap(Fuzzy.match(query: "te", candidate: "Open Terminal"))
        let midWord = try XCTUnwrap(Fuzzy.match(query: "te", candidate: "Steady"))

        XCTAssertGreaterThan(boundary.score, midWord.score)
    }

    func testCamelCaseHumpCountsAsWordBoundary() throws {
        let camel = try XCTUnwrap(Fuzzy.match(query: "ot", candidate: "openTerminal"))
        let plain = try XCTUnwrap(Fuzzy.match(query: "ot", candidate: "openterminal"))

        XCTAssertGreaterThan(camel.score, plain.score)
    }

    func testConsecutiveRanksAboveScattered() throws {
        let consecutive = try XCTUnwrap(Fuzzy.match(query: "abc", candidate: "abc"))
        let scattered = try XCTUnwrap(Fuzzy.match(query: "abc", candidate: "axbxc"))

        XCTAssertGreaterThan(consecutive.score, scattered.score)
    }

    func testShorterCandidateWinsWhenScoresTie() throws {
        // "Open" and "Open in New Tab" both match as a prefix; same score.
        let short = try XCTUnwrap(Fuzzy.match(query: "open", candidate: "Open"))
        let long = try XCTUnwrap(Fuzzy.match(query: "open", candidate: "Open in New Tab"))

        XCTAssertEqual(short.score, long.score)

        let ranked = Fuzzy.rank(
            ["Open in New Tab", "Reopen", "Open"],
            query: "open",
            text: { $0 }
        )

        XCTAssertEqual(ranked.first?.element, "Open")
    }

    // MARK: - Ranges (for highlighting)

    func testIndicesPointAtTheMatchedCharacters() throws {
        let match = try XCTUnwrap(Fuzzy.match(query: "ot", candidate: "open test"))

        XCTAssertEqual(match.indices, [0, 5])
        XCTAssertEqual(match.ranges, [0..<1, 5..<6])
    }

    func testRangesGroupConsecutiveIndices() throws {
        let match = try XCTUnwrap(Fuzzy.match(query: "test", candidate: "a test"))

        XCTAssertEqual(match.indices, [2, 3, 4, 5])
        XCTAssertEqual(match.ranges, [2..<6])
    }

    func testIndicesAreSortedAcrossTokens() throws {
        // "tt" matches late, "oo" early; indices must still come out ascending.
        let match = try XCTUnwrap(Fuzzy.match(query: "tt oo", candidate: "boot top"))

        XCTAssertEqual(match.indices, [1, 2, 3, 5])
    }

    func testEmptyQueryProducesNoRanges() throws {
        let match = try XCTUnwrap(Fuzzy.match(query: "", candidate: "anything"))

        XCTAssertEqual(match.ranges, [])
    }

    // MARK: - Ranking

    func testRankDropsNonMatchesAndKeepsOrder() {
        let candidates = ["Close Window", "Open Terminal", "Open in New Tab", "Preferences"]

        let ranked = Fuzzy.rank(candidates, query: "open", text: { $0 })

        XCTAssertEqual(ranked.map(\.element), ["Open Terminal", "Open in New Tab"])
    }

    func testRankOfEmptyQueryReturnsAllCandidates() {
        let ranked = Fuzzy.rank(["b", "a", "cc"], query: "", text: { $0 })

        // Equal scores, so the shortest come first, then alphabetical.
        XCTAssertEqual(ranked.map(\.element), ["a", "b", "cc"])
    }

    func testRankHandlesEmptyCandidateList() {
        XCTAssertTrue(Fuzzy.rank([String](), query: "open", text: { $0 }).isEmpty)
    }
}
