import XCTest
import ComicCore
@testable import XXComic

@MainActor
final class BuiltinSourceRegistrationTests: XCTestCase {
    func testHiperdexRegistrationConsumesStoredConfiguration() throws {
        let suite = "BuiltinSourceRegistrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        preferences.setConfig(SourceConfigItem(id: "hiperdex", name: "Configured HiperDEX", baseUrl: "https://fixture.invalid", referer: "https://fixture.invalid/ref/"), for: "hiperdex")
        let registered = AppEnvironment.createSources(preferences: preferences, browserSession: nil)
        let source = try XCTUnwrap(registered.first { $0.id == "hiperdex" })
        XCTAssertEqual(source.name, "Configured HiperDEX")
        XCTAssertEqual(source.referer, "https://fixture.invalid/ref/")
    }

    func testCurrentCatalogHasOneProductionAdapterPerAndroidSource() throws {
        let suite = "BuiltinSourceRegistrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SourcePreferences(defaults: defaults, defaultIDs: BuiltinSourceCatalog.activeIDs)
        let registered = AppEnvironment.createSources(preferences: preferences, browserSession: nil)
        let active = registered.filter { !BuiltinSourceCatalog.retiredIDs.contains($0.id) }
        XCTAssertEqual(active.map(\.id), preferences.orderedIDs)
        XCTAssertEqual(active.count, 51)
        // Display names from the frozen Android catalog, using a fresh preference suite.
        XCTAssertEqual(active.map(\.name), [
            "漫画160",
            "G社漫画",
            "18漫画",
            "禁漫天堂",
            "漫客栈",
            "HiperDEX",
            "漫画柜",
            "Hanman18",
            "悦看漫画",
            "漫本",
            "漫画栈",
            "比卡漫画",
            "tapmanga搬运",
            "催漫画",
            "六漫画",
            "拷贝漫画",
            "漫蛙",
            "顶漫画",
            "动漫啦",
            "新漫画-A",
            "再漫画",
            "瓜子漫画",
            "动漫屋",
            "极速漫画",
            "漫画人",
            "咚漫",
            "漫画狗",
            "思思漫画",
            "漫小肆",
            "乐乐韩漫",
            "图库漫画",
            "异次元漫画",
            "喵趣漫画",
            "艾米漫画",
            "毒牙漫画",
            "羞羞漫画",
            "歪歪漫画",
            "250漫画",
            "土豪漫画",
            "漫士多",
            "读漫屋",
            "次元漫",
            "W漫画",
            "阿吧漫画",
            "51漫画",
            "D漫画",
            "360漫画",
            "喜漫漫画",
            "天天看漫画",
            "来漫画",
            "L漫画"
        ])
        XCTAssertEqual(Set(registered.map(\.id)).count, registered.count)
        XCTAssertEqual(Set(registered.map(\.id)), Set(BuiltinSourceCatalog.activeIDs + ["baozimh", "mhua5"]))
    }
}
