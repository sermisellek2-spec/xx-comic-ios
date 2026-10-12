import XCTest

/// Drive the system provider UI; no selected URL or permission is injected.
struct FilesPickerDriver {
    let app: XCUIApplication
    var capture: (String) -> Void = { _ in }
    private let localNames = ["我的 iPhone", "我的 iPad", "On My iPhone", "On My iPad", "在我的 iPhone 上", "在我的 iPad 上"]
    private enum SelectionError: Error { case providerNotFound, folderNotOpened, fileNotFound, confirmationNotFound }

    func openFixtureProvider() throws {
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@ AND identifier != %@", ["取消", "Cancel"], "source.config.cancel")).firstMatch
        guard cancel.waitForExistence(timeout: 10) else { throw SelectionError.providerNotFound }
        let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse"])).firstMatch
        let local = app.cells.containing(NSPredicate(format: "label IN %@", localNames)).firstMatch
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse", "位置", "Locations", "返回", "Back"] + localNames)).firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["显示边栏", "Show Sidebar"])).firstMatch
        let provider = app.cells.containing(.staticText, identifier: "XXComic Files Fixture").firstMatch
        let providerTitle = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "XXComic Files Fixture,")).firstMatch
        for _ in 0..<10 {
            if providerTitle.exists { capture("provider-root"); return }
            if provider.exists && provider.isHittable {
                provider.tap()
                guard providerTitle.waitForExistence(timeout: 10) else { throw SelectionError.providerNotFound }
                capture("provider-root"); return
            }
            if browse.exists && !browse.isSelected { browse.tap() }
            else if local.exists && local.isHittable { local.tap() }
            else if back.exists && back.isHittable { back.tap() }
            else if sidebar.exists && sidebar.isHittable { sidebar.tap() }
            else {
                let parent = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["XXComic Files Fixture"])).firstMatch
                if parent.exists && parent.isHittable { parent.tap() }
                else { break }
            }
        }
        throw SelectionError.providerNotFound
    }

    func openFolder(_ name: String) throws {
        let cell = app.cells.containing(.staticText, identifier: name).firstMatch
        guard cell.waitForExistence(timeout: 10) else { throw SelectionError.folderNotOpened }
        // In a folder chooser the icon supports opening a folder. Text taps may
        // select it; the navigation bar itself has a fixed DOC identifier.
        let icon = cell.images.firstMatch
        if icon.exists && icon.isHittable { icon.doubleTap() } else { cell.doubleTap() }
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        let legacyTitle = app.navigationBars[name]
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in title.exists || legacyTitle.exists }, object: app)
        guard XCTWaiter.wait(for: [opened], timeout: 10) == .completed else { throw SelectionError.folderNotOpened }
        capture("target-folder")
    }

    func selectFile(_ name: String) throws {
        let stem = (name as NSString).deletingPathExtension
        let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", name, stem)).firstMatch
        guard file.waitForExistence(timeout: 10) else { throw SelectionError.fileNotFound }
        file.tap()
    }

    func confirmFolder() throws { try confirm(["打开", "Open", "完成", "Done"]) }
    func confirmExport() throws { try confirm(["导出", "存储", "保存", "拷贝", "移动", "Export", "Save", "Copy", "Move"]) }
    private func confirm(_ labels: [String]) throws {
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        guard button.waitForExistence(timeout: 10), button.isEnabled else { throw SelectionError.confirmationNotFound }
        button.tap()
    }
}
