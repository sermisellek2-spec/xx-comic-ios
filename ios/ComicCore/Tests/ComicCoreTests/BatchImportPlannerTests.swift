import XCTest
@testable import ComicCore

final class BatchImportPlannerTests: XCTestCase {
    func testExplicitMergeSortsDifferentTitlesWithoutRegroupingOrMutatingInput() throws {
        let later = try BatchImportCandidate(seriesTitle: "Different A", fileName: "A.epub", sourceOrder: "3")
        let earlier = try BatchImportCandidate(seriesTitle: "Different Z", fileName: "Z.mobi", sourceOrder: "1")
        let input = [later, earlier]
        XCTAssertEqual(BatchImportPlanner.orderVolumes(input), [earlier, later])
        XCTAssertEqual(input, [later, earlier])
    }

    func testDecimalMetadataWinsOverFileName() throws {
        let later = try BatchImportCandidate(seriesTitle: "Series", fileName: "A.epub", sourceOrder: "2.5")
        let earlier = try BatchImportCandidate(seriesTitle: "Series", fileName: "Z.epub", sourceOrder: "2.0")
        let groups = BatchImportPlanner.plan([later, earlier])
        XCTAssertEqual(groups.first?.volumes.map(\.fileName), ["Z.epub", "A.epub"])
        XCTAssertEqual(groups.first?.requiresConfirmation, true)
    }

    func testRemoteFilesGroupBySourceAndComicAndSortByVolume() throws {
        let files = try ["城市猎人_10.epub", "城市猎人_2.epub", "城市猎人_01.epub"].enumerated().map {
            try BatchImportCandidate(sourceId: "kzo", remoteComicId: "10872", fileName: $0.element,
                                     fingerprint: "hash\($0.offset)", selectionIndex: $0.offset)
        }
        let groups = BatchImportPlanner.plan(files)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.key, "remote:kzo:10872")
        XCTAssertEqual(groups.first?.requiresConfirmation, false)
        XCTAssertEqual(groups.first?.volumes.map(\.fileName), ["城市猎人_01.epub", "城市猎人_2.epub", "城市猎人_10.epub"])
    }

    func testLocalSameTitlesOnlySuggestGroupingAndRequireConfirmation() throws {
        let files = try ["城市猎人 第02卷.epub", "城市猎人 第01卷.mobi"].map { try BatchImportCandidate(fileName: $0) }
        let groups = BatchImportPlanner.plan(files)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "城市猎人")
        XCTAssertEqual(groups.first?.requiresConfirmation, true)
    }

    func testDuplicateFingerprintRetainsFirstCandidate() throws {
        let first = try BatchImportCandidate(sourceId: "source", remoteComicId: "comic", fileName: "第一卷.epub", fingerprint: "same")
        let copy = try BatchImportCandidate(sourceId: "source", remoteComicId: "comic", fileName: "第一卷-copy.epub", fingerprint: "SAME")
        XCTAssertEqual(BatchImportPlanner.plan([first, copy]).first?.volumes, [first])
    }

    func testExplicitOrderWinsOverFilenameOrder() throws {
        let first = try BatchImportCandidate(sourceId: "source", remoteComicId: "comic", fileName: "卷10.epub", sourceOrder: "0")
        let second = try BatchImportCandidate(sourceId: "source", remoteComicId: "comic", fileName: "卷01.epub", sourceOrder: "1")
        XCTAssertEqual(BatchImportPlanner.plan([first, second]).first?.volumes, [first, second])
    }

    func testGroupOrderIsFirstAppearanceAndFingerprintDedupIsLocal() throws {
        let files = try [
            BatchImportCandidate(seriesTitle: "Zulu", fileName: "Z", fileId: "same", fingerprint: "HASH"),
            BatchImportCandidate(seriesTitle: "Alpha", fileName: "A", fileId: "same", fingerprint: "hash"),
            BatchImportCandidate(seriesTitle: "zULU", fileName: "B", fingerprint: "hash"),
            BatchImportCandidate(seriesTitle: "Zulu", fileName: "Z", fileId: "same"),
            BatchImportCandidate(seriesTitle: "Zulu", fileName: "Z", fileId: "same")
        ]
        let groups = BatchImportPlanner.plan(files)
        XCTAssertEqual(groups.map(\.key), ["local:zulu", "local:alpha"])
        XCTAssertEqual(groups.map(\.title), ["Zulu", "Alpha"])
        XCTAssertEqual(groups[0].volumes, [files[0], files[3], files[4]])
        XCTAssertEqual(groups[1].volumes, [files[1]])
        XCTAssertTrue(BatchImportPlanner.plan([]).isEmpty)
    }

    func testRemoteIdentityRequiresBothIDsAndKeepsSourceDistinct() throws {
        let files = try [
            BatchImportCandidate(sourceId: "one", remoteComicId: "id", seriesTitle: "Series"),
            BatchImportCandidate(sourceId: "two", remoteComicId: "id", seriesTitle: "Series"),
            BatchImportCandidate(sourceId: "one", seriesTitle: "Series"),
            BatchImportCandidate(remoteComicId: "id", seriesTitle: "Series")
        ]
        let groups = BatchImportPlanner.plan(files)
        XCTAssertEqual(groups.map(\.key), ["remote:one:id", "remote:two:id", "local:series"])
        XCTAssertEqual(groups.map(\.requiresConfirmation), [false, false, true])
        XCTAssertEqual(groups.map { $0.volumes.count }, [1, 1, 2])
    }

    func testCanonicalEquivalentLocalNamesRemainSeparateGroups() throws {
        let groups = BatchImportPlanner.plan(try ["Café", "Cafe\u{0301}"].map { try BatchImportCandidate(seriesTitle: $0) })
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { Array($0.key.utf16) }, [Array("local:café".utf16), Array("local:cafe\u{0301}".utf16)])
    }

    func testCanonicalEquivalentRemoteIDsRemainSeparateGroups() throws {
        let groups = BatchImportPlanner.plan(try ["é", "e\u{0301}"].map { try BatchImportCandidate(sourceId: "source", remoteComicId: $0) })
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { Array($0.key.utf16) }, [Array("remote:source:é".utf16), Array("remote:source:e\u{0301}".utf16)])
    }

    func testFingerprintUsesJavaCaseInsensitivityWithoutNormalizationOrExpansion() throws {
        for pair in [("I", "ı"), ("İ", "i"), ("ς", "σ"), ("ſ", "S"), ("ß", "ẞ"), ("ᾀ", "ᾈ")] {
            let files = try [pair.0, pair.1].map { try BatchImportCandidate(seriesTitle: "Series", fingerprint: $0) }
            XCTAssertEqual(BatchImportPlanner.plan(files).first?.volumes.count, 1, "\(pair)")
        }
        for pair in [("é", "e\u{0301}"), ("ß", "ss"), ("ßs", "sß"), ("ﬀ", "ff")] {
            let files = try [pair.0, pair.1].map { try BatchImportCandidate(seriesTitle: "Series", fingerprint: $0) }
            XCTAssertEqual(BatchImportPlanner.plan(files).first?.volumes.count, 2, "\(pair)")
        }
    }

    func testCandidateTrimsJavaWhitespacePreservesOrderTextAndClampsSelection() throws {
        let candidate = try BatchImportCandidate(sourceId: "\0 a \t", remoteComicId: " b\r", seriesTitle: " c ",
                                                fileName: " d ", fileId: " e ", sourceOrder: " +02.00e+1\n",
                                                format: " f ", fingerprint: " g ", selectionIndex: -1)
        XCTAssertEqual([candidate.sourceId, candidate.remoteComicId, candidate.seriesTitle, candidate.fileName,
                        candidate.fileId, candidate.format, candidate.fingerprint], ["a", "b", "c", "d", "e", "f", "g"])
        XCTAssertEqual(candidate.sourceOrder, "+02.00e+1")
        XCTAssertEqual(candidate.selectionIndex, 0)
        XCTAssertNil(try BatchImportCandidate(sourceOrder: " \t\r").sourceOrder)
        XCTAssertEqual(try BatchImportCandidate(seriesTitle: "\u{a0}Series\u{a0}").seriesTitle, "\u{a0}Series\u{a0}")
        XCTAssertEqual(try BatchImportCandidate(), try BatchImportCandidate(sourceOrder: ""))
    }

    func testNormalizeTitleMatchesAndroidStepsAndASCIIRegexRules() {
        let examples: [(String, String)] = [
            (" 城市猎人 第02卷.epub ", "城市猎人"), ("Book_Vol. 002.CBZ", "Book"),
            ("Book-volume12.mobi", "Book"), ("Book v3.epub", "Book"), ("Book 0004.epub", "Book"),
            ("Book [02].epub", "Book [02]"), ("Book (02).epub", "Book (02)"),
            ("Book 第2卷 Extra.epub", "Book 第2卷 Extra"), ("A\t \n B_-.epub", "A B"),
            ("Book\u{3000}第2卷.epub", "Book"), ("Book\u{a0}第2卷.epub", "Book\u{a0}"),
            ("Book Vol\u{a0}2.epub", "Book Vol\u{a0}"), ("Book 第０２卷.epub", "Book 第０２卷"),
            ("Book.abcdefghi", "Book.abcdefghi"), ("Book.é", "Book.é"),
            ("Book.A1B2C3D4", "Book"), ("第2卷.epub", "未命名漫画"), (" \t", "未命名漫画")
        ]
        for (input, expected) in examples { XCTAssertEqual(BatchImportPlanner.normalizeTitle(input), expected, input) }
    }

    func testVolumeNumberKeepsLastSuccessfulInt32MatchAndASCIIOnly() {
        let examples: [(String, Int)] = [
            ("Book 第02卷.epub", 2), ("第3册 第4集 第5话 第6章", 6),
            ("Book VoLuMe. 12.epub", 12), ("v3", 3), ("Book (004).epub", 4), ("Book [12].epub", 12),
            ("0000.epub", 0), ("Book 1234.epub", 1234), ("Book 12345.epub", -1),
            ("Book 第12卷 Extra 第3卷.epub", 3), ("第7卷 v2147483648", 7),
            ("v2147483647", 2147483647), ("v2147483648", -1), ("v0000000000000000000000000002", 2),
            ("Vol\u{a0}2", -1), ("第\u{a0}2卷", -1), ("Book\u{a0}2.epub", -1),
            ("Book 第０２卷.epub", -1), ("Book １２.epub", -1), ("Book_2１２.epub", 2), ("", -1)
        ]
        for (input, expected) in examples { XCTAssertEqual(BatchImportPlanner.volumeNumber(input), expected, input) }
    }

    func testMetadataPresenceVolumeNaturalNameSelectionAndStableTies() throws {
        let files = try [
            BatchImportCandidate(fileName: "A", fileId: "missing"),
            BatchImportCandidate(fileName: "Z 第0卷", fileId: "volume"),
            BatchImportCandidate(fileName: "Z", fileId: "metadata", sourceOrder: "9"),
            BatchImportCandidate(fileName: "B 第2卷", fileId: "second", sourceOrder: "2.0"),
            BatchImportCandidate(fileName: "A 第2卷", fileId: "natural", sourceOrder: "2"),
            BatchImportCandidate(fileName: "Z 第1卷", fileId: "first", sourceOrder: "2.00"),
            BatchImportCandidate(fileName: "A 第2卷", fileId: "late-selection", sourceOrder: "2", selectionIndex: 8),
            BatchImportCandidate(fileName: "A 第2卷", fileId: "stable", sourceOrder: "2")
        ]
        XCTAssertEqual(BatchImportPlanner.orderVolumes(files).map(\.fileId),
                       ["first", "natural", "stable", "late-selection", "second", "metadata", "volume", "missing"])
    }

    func testExactDecimalsNegativeZeroExponentAndBeyond38Digits() throws {
        let values = ["1e3", "0.001", "-0", "-1e-3", "-1000", "1e-3", "+0.000e12",
                      "123456789012345678901234567890123456789.000000000000000000002",
                      "123456789012345678901234567890123456789.000000000000000000001", ".5", "1."]
        let files = try values.enumerated().map { try BatchImportCandidate(fileName: "same", fileId: String($0.offset), sourceOrder: $0.element) }
        XCTAssertEqual(BatchImportPlanner.orderVolumes(files).map(\.fileId), ["4", "3", "2", "6", "1", "5", "9", "10", "0", "8", "7"])
    }

    func testHugeExponentsCompareWithoutExpandingZeros() throws {
        let values = ["1e2147483647", "1e-2147483647", "10e2147483647", "-1e2147483647", "0e2147483647", "0.1e2147483647"]
        let files = try values.enumerated().map { try BatchImportCandidate(fileName: "same", fileId: String($0.offset), sourceOrder: $0.element) }
        XCTAssertEqual(BatchImportPlanner.orderVolumes(files).map(\.fileId), ["3", "4", "1", "5", "0", "2"])
    }

    func testInvalidDecimalAndJavaExponentScaleOverflowFailExplicitly() {
        for value in ["NaN", "Infinity", "+", ".", "1e", "1e+", "1e1.0", "1 2", "1,2", "1_2", "0x1", "１", "1\u{a0}",
                      "1e2147483648", "1e-2147483648", "1.0e-2147483647", "1e99999999999999999999", "1.2.3"] {
            XCTAssertThrowsError(try BatchImportCandidate(sourceOrder: value), value)
        }
    }

    func testSourceOrderTextHasOneMiBLimit() throws {
        let atLimit = "1" + String(repeating: "0", count: 1_048_575)
        let huge = try BatchImportCandidate(fileId: "huge", sourceOrder: atLimit)
        let tiny = try BatchImportCandidate(fileId: "tiny", sourceOrder: "1")
        XCTAssertEqual(BatchImportPlanner.orderVolumes([huge, tiny]).map(\.fileId), ["tiny", "huge"])
        XCTAssertThrowsError(try BatchImportCandidate(sourceOrder: atLimit + "0"))
    }
}
