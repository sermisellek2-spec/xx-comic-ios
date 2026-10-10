import XCTest
@testable import ComicCore

final class SourceGroupStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SourceGroupStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testInitialGroupsHasOnlyBuiltinAll() {
        let store = SourceGroupStore(directory: tempDirectory)
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].id, SourceGroupStore.allId)
        XCTAssertEqual(store.groups[0].name, SourceGroupStore.defaultGroupName)
        XCTAssertTrue(store.groups[0].isBuiltin)
        XCTAssertEqual(store.currentGroup.id, SourceGroupStore.allId)
    }

    func testCreateGroupAndValidation() throws {
        let store = SourceGroupStore(directory: tempDirectory)
        let group = try store.create(name: "日漫精选", sourceIds: ["copymanga", "manhuagui"])
        XCTAssertEqual(group.name, "日漫精选")
        XCTAssertFalse(group.isBuiltin)
        XCTAssertEqual(group.sourceIds, ["copymanga", "manhuagui"])
        XCTAssertEqual(store.groups.count, 2)

        // Empty name throws
        XCTAssertThrowsError(try store.create(name: "   ")) { error in
            guard case SourceGroupError.emptyName = error else {
                XCTFail("Expected emptyName error, got \(error)")
                return
            }
        }

        // Duplicate name throws (case-insensitive)
        XCTAssertThrowsError(try store.create(name: "日漫精选")) { error in
            guard case SourceGroupError.duplicateName = error else {
                XCTFail("Expected duplicateName error, got \(error)")
                return
            }
        }
        XCTAssertThrowsError(try store.create(name: "全部")) { error in
            guard case SourceGroupError.duplicateName = error else {
                XCTFail("Expected duplicateName error for '全部', got \(error)")
                return
            }
        }
    }

    func testRenameAndBuiltinProtection() throws {
        let store = SourceGroupStore(directory: tempDirectory)
        let group = try store.create(name: "国漫", sourceIds: ["kuaikan"])

        // Cannot rename builtin
        XCTAssertThrowsError(try store.rename(id: SourceGroupStore.allId, to: "新名字")) { error in
            guard case SourceGroupError.builtinImmutable = error else {
                XCTFail("Expected builtinImmutable error, got \(error)")
                return
            }
        }

        // Rename custom
        try store.rename(id: group.id, to: "热门国漫")
        XCTAssertEqual(store.groups.first(where: { $0.id == group.id })?.name, "热门国漫")
    }

    func testSetSources() throws {
        let store = SourceGroupStore(directory: tempDirectory)
        let group = try store.create(name: "测试组", sourceIds: ["a"])
        try store.setSources(id: group.id, sourceIds: ["b", "c"])
        XCTAssertEqual(store.groups.first(where: { $0.id == group.id })?.sourceIds, ["b", "c"])
    }

    func testDeleteAndSelectionReset() throws {
        let store = SourceGroupStore(directory: tempDirectory)
        let group = try store.create(name: "待删组", sourceIds: ["x"])
        try store.select(id: group.id)
        XCTAssertEqual(store.selectedId, group.id)

        // Cannot delete builtin
        XCTAssertThrowsError(try store.delete(id: SourceGroupStore.allId))

        // Delete group resets selection to allId
        try store.delete(id: group.id)
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.selectedId, SourceGroupStore.allId)
    }

    func testVisibleSourcesFiltering() throws {
        let store = SourceGroupStore(directory: tempDirectory)
        struct MockSource {
            let id: String
            let name: String
        }
        let allSources = [
            MockSource(id: "copymanga", name: "拷贝"),
            MockSource(id: "manhuagui", name: "漫画柜"),
            MockSource(id: "mh160", name: "160")
        ]

        // When "全部" is selected, all enabled sources are returned
        let visibleAll = store.visibleSources(allSources, idExtractor: \.id)
        XCTAssertEqual(visibleAll.map(\.id), ["copymanga", "manhuagui", "mh160"])

        // Create and select custom group
        let group = try store.create(name: "仅拷贝与160", sourceIds: ["copymanga", "mh160"])
        try store.select(id: group.id)

        let visibleCustom = store.visibleSources(allSources, idExtractor: \.id)
        XCTAssertEqual(visibleCustom.map(\.id), ["copymanga", "mh160"])
    }

    func testPersistenceAndReload() throws {
        let store1 = SourceGroupStore(directory: tempDirectory)
        let group = try store1.create(name: "持久化测试", sourceIds: ["s1", "s2"])
        try store1.select(id: group.id)

        // Reload fresh instance from disk
        let store2 = SourceGroupStore(directory: tempDirectory)
        XCTAssertEqual(store2.groups.count, 2)
        XCTAssertEqual(store2.selectedId, group.id)
        XCTAssertEqual(store2.currentGroup.name, "持久化测试")
        XCTAssertEqual(store2.currentGroup.sourceIds, ["s1", "s2"])
    }

    func testCorruptedFileRecoversFromBackup() throws {
        let store1 = SourceGroupStore(directory: tempDirectory)
        _ = try store1.create(name: "备份测试", sourceIds: ["b1"])
        // Creating another group triggers rotation to backup
        _ = try store1.create(name: "备份测试2", sourceIds: ["b2"])

        let primaryURL = tempDirectory.appendingPathComponent("source_groups.json")
        // Corrupt primary
        try "corrupted json content".write(to: primaryURL, atomically: true, encoding: .utf8)

        let store2 = SourceGroupStore(directory: tempDirectory)
        XCTAssertEqual(store2.recoveryMessage, "分组文件已从备份恢复，请检查当前分组")
        XCTAssertEqual(store2.groups.count, 2) // builtin + 1 custom from previous snapshot
        XCTAssertEqual(store2.groups[1].name, "备份测试")
    }
}
