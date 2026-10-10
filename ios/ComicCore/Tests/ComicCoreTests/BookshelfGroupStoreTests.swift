import XCTest
@testable import ComicCore

final class BookshelfGroupStoreTests: XCTestCase {
    private var tempDir: URL!
    private var storeFile: URL!
    private var store: BookshelfGroupStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeFile = tempDir.appendingPathComponent("bookshelf_groups.json")
        store = BookshelfGroupStore(file: storeFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testBuiltinGroupsExistByDefaultAndCannotBeDeletedOrRenamed() {
        let onlineGroups = store.getGroups(scope: .online)
        let localGroups = store.getGroups(scope: .local)

        XCTAssertEqual(onlineGroups.count, 1)
        XCTAssertEqual(onlineGroups.first?.id, BookshelfGroupStore.builtinOnlineAllId)
        XCTAssertEqual(onlineGroups.first?.name, "全部")
        XCTAssertTrue(onlineGroups.first?.isBuiltin == true)

        XCTAssertEqual(localGroups.count, 1)
        XCTAssertEqual(localGroups.first?.id, BookshelfGroupStore.builtinLocalAllId)
        XCTAssertEqual(localGroups.first?.name, "全部")
        XCTAssertTrue(localGroups.first?.isBuiltin == true)

        // Deleting builtin throws error
        XCTAssertThrowsError(try store.deleteGroup(id: BookshelfGroupStore.builtinOnlineAllId))
        XCTAssertThrowsError(try store.deleteGroup(id: BookshelfGroupStore.builtinLocalAllId))

        // Renaming builtin throws error
        XCTAssertThrowsError(try store.renameGroup(id: BookshelfGroupStore.builtinOnlineAllId, rawNewName: "新名字"))
    }

    func testCreateRenameAndReorderCustomGroups() throws {
        let g1 = try store.createGroup(scope: .online, rawName: "  热血  ")
        XCTAssertEqual(g1.name, "热血")
        XCTAssertFalse(g1.isBuiltin)
        XCTAssertEqual(g1.scope, .online)

        let g2 = try store.createGroup(scope: .online, rawName: "搞笑")
        XCTAssertEqual(g2.name, "搞笑")

        // Reject empty or whitespace
        XCTAssertThrowsError(try store.createGroup(scope: .online, rawName: "   "))

        // Reject duplicates in same scope
        XCTAssertThrowsError(try store.createGroup(scope: .online, rawName: "热血"))

        // Allow same name in different scope
        let localG = try store.createGroup(scope: .local, rawName: "热血")
        XCTAssertEqual(localG.name, "热血")
        XCTAssertEqual(localG.scope, .local)

        // Rename g1
        let renamed = try store.renameGroup(id: g1.id, rawNewName: "冒险")
        XCTAssertEqual(renamed.name, "冒险")
        XCTAssertEqual(store.getGroup(id: g1.id)?.name, "冒险")

        // Reorder
        store.reorderGroups(scope: .online, orderedCustomGroupIds: [g2.id, g1.id])
        let groups = store.getGroups(scope: .online)
        XCTAssertEqual(groups.map(\.id), [BookshelfGroupStore.builtinOnlineAllId, g2.id, g1.id])
    }

    func testDeleteAndRestoreSnapshot() throws {
        let g = try store.createGroup(scope: .online, rawName: "恋爱")
        store.addToGroup(groupId: g.id, comicId: "comic_123")
        store.addToGroup(groupId: g.id, comicId: "comic_456")

        XCTAssertTrue(store.containsComic(groupId: g.id, comicId: "comic_123"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "comic_123"))

        // Delete
        let snapshot = try store.deleteGroup(id: g.id)
        XCTAssertEqual(snapshot.group.name, "恋爱")
        XCTAssertEqual(Set(snapshot.memberIds), Set(["comic_123", "comic_456"]))

        // Group is gone, but comics remain in builtin "全部"
        XCTAssertNil(store.getGroup(id: g.id))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "comic_123"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "comic_456"))

        // Restore
        let restored = store.restoreGroup(snapshot: snapshot)
        XCTAssertEqual(restored.id, g.id)
        XCTAssertEqual(restored.name, "恋爱")
        XCTAssertTrue(store.containsComic(groupId: restored.id, comicId: "comic_123"))
        XCTAssertTrue(store.containsComic(groupId: restored.id, comicId: "comic_456"))
    }

    func testMemberOperationsAndScopeRemoval() throws {
        let g1 = try store.createGroup(scope: .online, rawName: "奇幻")
        let g2 = try store.createGroup(scope: .online, rawName: "科幻")

        store.addToGroup(groupId: g1.id, comicId: "c1")
        store.addToGroup(groupId: g2.id, comicId: "c1")
        XCTAssertEqual(store.getGroupsForComic(scope: .online, comicId: "c1").map(\.name), ["全部", "奇幻", "科幻"])

        // Remove from single group g1
        store.removeFromGroup(groupId: g1.id, comicId: "c1")
        XCTAssertFalse(store.containsComic(groupId: g1.id, comicId: "c1"))
        XCTAssertTrue(store.containsComic(groupId: g2.id, comicId: "c1"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "c1"))

        // Update groups
        store.updateComicGroups(scope: .online, comicId: "c1", targetGroupIds: [g1.id])
        XCTAssertTrue(store.containsComic(groupId: g1.id, comicId: "c1"))
        XCTAssertFalse(store.containsComic(groupId: g2.id, comicId: "c1"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "c1"))

        // Remove from builtin "全部" removes from ALL groups in that scope
        store.removeFromGroup(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "c1")
        XCTAssertFalse(store.containsComic(groupId: g1.id, comicId: "c1"))
        XCTAssertFalse(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "c1"))
        XCTAssertTrue(store.getGroupsForComic(scope: .online, comicId: "c1").isEmpty)
    }

    func testLegacyDataMigration() {
        XCTAssertFalse(store.isMigrated)
        store.migrateLegacyDataIfNeeded(
            legacyOnlineFavorites: ["fav_1", "fav_2"],
            legacyLocalBookIds: ["local_1"]
        )
        XCTAssertTrue(store.isMigrated)
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "fav_1"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "fav_2"))
        XCTAssertTrue(store.containsComic(groupId: BookshelfGroupStore.builtinLocalAllId, comicId: "local_1"))

        // Idempotent: second run does nothing
        store.migrateLegacyDataIfNeeded(legacyOnlineFavorites: ["fav_3"], legacyLocalBookIds: nil)
        XCTAssertFalse(store.containsComic(groupId: BookshelfGroupStore.builtinOnlineAllId, comicId: "fav_3"))
    }

    func testBookshelfLayoutHelper() {
        let defaults = UserDefaults(suiteName: "BookshelfLayoutHelperTests." + UUID().uuidString)!
        XCTAssertTrue(BookshelfLayoutHelper.isGridMode(defaults: defaults, scope: .online))
        XCTAssertTrue(BookshelfLayoutHelper.isGridMode(defaults: defaults, scope: .local))

        BookshelfLayoutHelper.setGridMode(defaults: defaults, scope: .online, isGrid: false)
        XCTAssertFalse(BookshelfLayoutHelper.isGridMode(defaults: defaults, scope: .online))
        XCTAssertTrue(BookshelfLayoutHelper.isGridMode(defaults: defaults, scope: .local))

        XCTAssertEqual(BookshelfLayoutHelper.resolveBadgeColor(hasUpdate: true), 0xFF2B98D9)
        XCTAssertEqual(BookshelfLayoutHelper.resolveBadgeColor(hasUpdate: false), 0xFF8A9AA8)

        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: 0), "")
        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: 5), "5")
        XCTAssertEqual(BookshelfLayoutHelper.formatUnreadBadgeText(count: 100), "99+")

        XCTAssertEqual(BookshelfLayoutHelper.calculateOnlineUnreadCount(totalChapters: 0, savedChapter: 0, hasReadHistory: false), -1)
        XCTAssertEqual(BookshelfLayoutHelper.calculateOnlineUnreadCount(totalChapters: 10, savedChapter: 0, hasReadHistory: false), 10)
        XCTAssertEqual(BookshelfLayoutHelper.calculateOnlineUnreadCount(totalChapters: 10, savedChapter: 3, hasReadHistory: true), 6)

        XCTAssertEqual(BookshelfLayoutHelper.formatOnlineLatestChapter(nil), "暂无更新")
        XCTAssertEqual(BookshelfLayoutHelper.formatOnlineLatestChapter(""), "暂无更新")
        XCTAssertEqual(BookshelfLayoutHelper.formatOnlineLatestChapter("第10话"), "更新至 第10话")
        XCTAssertEqual(BookshelfLayoutHelper.formatOnlineLatestChapter("更新至 第10话"), "更新至 第10话")
    }
}
