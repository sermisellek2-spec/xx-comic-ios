import XCTest
@testable import ComicCore

final class ComicDirectoryPreparationTests: XCTestCase {
    private let summary = ComicSummary(sourceId: "fixture", comicId: "comic", title: "目录按需加载")
    private let chapters = [
        Chapter(chapterId: "one", title: "第1话", url: "http://127.0.0.1/chapter/1"),
        Chapter(chapterId: "two", title: "第2话", url: "http://127.0.0.1/chapter/2")
    ]

    private func detail(chapters: [Chapter] = []) -> ComicDetail {
        ComicDetail(summary: summary, author: "作者", status: "连载中", description: "简介",
                    latestChapter: "第2话", chapters: chapters)
    }

    func testOnDemandDirectoryReachesSelectionWithoutLosingMetadata() async throws {
        let result = try await detail().ensuringChapters { self.chapters }
        XCTAssertEqual(result.chapters.map(\.chapterId), ["one", "two"])
        XCTAssertEqual(result.summary, summary)
        XCTAssertEqual(result.author, "作者")
        XCTAssertEqual(result.status, "连载中")
        XCTAssertEqual(result.description, "简介")
        XCTAssertEqual(result.latestChapter, "第2话")
    }

    func testCachedDirectoryRemainsUsableWhenDirectoryServiceIsUnavailable() async throws {
        let result = try await detail(chapters: chapters).ensuringChapters {
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(result.chapters.map(\.chapterId), ["one", "two"])
    }

    func testEmptyDirectoryIsAnErrorAndCanBeRetried() async throws {
        do {
            _ = try await detail().ensuringChapters { [] }
            XCTFail("An empty directory must not open an unusable download selector")
        } catch {
            XCTAssertEqual(error as? ComicDirectoryError, .empty)
        }
        let result = try await detail().ensuringChapters { self.chapters }
        XCTAssertEqual(result.chapters.count, 2)
    }

    func testDirectoryFailureIsPreservedForRetryAndVerification() async throws {
        do {
            _ = try await detail().ensuringChapters { throw Mh18SourceError.verificationRequired }
            XCTFail("Verification errors must reach the visible caller")
        } catch {
            XCTAssertEqual(error as? Mh18SourceError, .verificationRequired)
        }
    }

    func testCancelledRequestCannotReturnCachedDirectory() async throws {
        let cached = detail(chapters: chapters)
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cached.ensuringChapters { [] }
        }
        do {
            _ = try await request.value
            XCTFail("Cancellation must stop the selection from opening")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancellationDuringLoaderRejectsItsLateResult() async throws {
        let empty = detail(), loaded = chapters
        let request = Task {
            try await empty.ensuringChapters {
                withUnsafeCurrentTask { $0?.cancel() }
                return loaded
            }
        }
        do {
            _ = try await request.value
            XCTFail("A loader that ignores cancellation must not return a usable directory")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
