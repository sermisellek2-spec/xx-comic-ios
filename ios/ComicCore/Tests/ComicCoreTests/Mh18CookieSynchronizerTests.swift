import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ComicCore

final class Mh18CookieSynchronizerTests: XCTestCase {
    @MainActor
    func testOldSnapshotCannotReleaseRequestBeforeNewCookieIsApplied() async {
        await verifyInterleaving(latest: [cookie(value: "verified")], expected: "verified")
    }

    @MainActor
    func testOldSnapshotCannotReleaseRequestWithDeletedCookieOrDeleteOtherSites() async {
        await verifyInterleaving(latest: [], expected: nil)
    }

    @MainActor
    private func verifyInterleaving(latest: [HTTPCookie], expected: String?) async {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "mh18-test-" + UUID().uuidString)
        storage.setCookie(cookie(value: "old"))
        storage.setCookie(cookie(value: "unrelated", domain: "other.example"))
        defer { for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) } }
        let sync = Mh18CookieSynchronizer()
        let snapshots = Snapshots()
        var requestFinished = false
        var sentCookie: String?
        let request = Task {
            await sync.synchronize(read: snapshots.read, storage: storage)
            sentCookie = storage.cookies(for: URL(string: "https://18mh.org/manga")!)?.first?.value
            requestFinished = true
        }
        await fulfillment(of: [snapshots.started[0]], timeout: 2)
        sync.invalidate()
        let observer = Task { await sync.synchronize(read: snapshots.read, storage: storage) }
        await fulfillment(of: [snapshots.started[1]], timeout: 2)
        snapshots.resolve(0, with: [cookie(value: "old")])
        // A must take a fresh snapshot while B is still pending, not release the HTTP request.
        await fulfillment(of: [snapshots.started[2]], timeout: 2)
        XCTAssertFalse(requestFinished)
        snapshots.resolve(1, with: latest)
        await observer.value
        snapshots.resolve(2, with: latest)
        await request.value
        XCTAssertEqual(sentCookie, expected)
        XCTAssertEqual(storage.cookies(for: URL(string: "https://other.example/")!)?.first?.value, "unrelated")
    }

    private func cookie(value: String, domain: String = "18mh.org") -> HTTPCookie {
        HTTPCookie(properties: [.domain: domain, .path: "/", .name: "cf_clearance", .value: value, .secure: "TRUE"])!
    }
}

@MainActor
private final class Snapshots {
    let started = (0..<3).map { XCTestExpectation(description: "snapshot \($0)") }
    private var pending: [Int: CheckedContinuation<[HTTPCookie], Never>] = [:]
    private var count = 0
    func read() async -> [HTTPCookie] {
        let id = count
        count += 1
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            if started.indices.contains(id) { started[id].fulfill() }
        }
    }
    func resolve(_ id: Int, with cookies: [HTTPCookie]) { pending.removeValue(forKey: id)?.resume(returning: cookies) }
}
