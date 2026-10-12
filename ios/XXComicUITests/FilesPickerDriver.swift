import XCTest

/// Drive the system provider UI; no selected URL or permission is injected.
struct FilesPickerDriver {
    let app: XCUIApplication
    var capture: (String) -> Void = { _ in }
    private let localNames = ["我的 iPhone", "我的 iPad", "On My iPhone", "On My iPad", "在我的 iPhone 上", "在我的 iPad 上"]
    private enum SelectionError: Error { case providerNotFound, folderNotOpened, fileNotFound, confirmationNotFound, cancellationNotCompleted }

    private var pickerBar: XCUIElement { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"] }

    private func isShowingFolder(_ name: String) -> Bool {
        pickerBar.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch.exists
            || pickerBar.staticTexts[name].exists || app.navigationBars[name].exists
    }

    func openFixtureProvider() throws {
        guard pickerBar.waitForExistence(timeout: 10) else { throw SelectionError.providerNotFound }
        capture("provider-start")
        let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse"])).firstMatch
        let local = app.cells.containing(NSPredicate(format: "label IN %@", localNames)).firstMatch
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse", "位置", "Locations", "返回", "Back"] + localNames)).firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["显示边栏", "Show Sidebar"])).firstMatch
        let provider = app.cells.containing(.staticText, identifier: "XXComic Files Fixture").firstMatch
        for _ in 0..<10 {
            if isShowingFolder("XXComic Files Fixture") { capture("provider-root"); return }
            if provider.exists && provider.isHittable {
                try openFolder("XXComic Files Fixture")
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
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isShowingFolder(name) }, object: app)
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
    func cancelPicker() throws {
        guard pickerBar.waitForExistence(timeout: 15) else { throw SelectionError.providerNotFound }
        let cancel = pickerBar.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // Folder/export sheets on iPhone expose a pull-down dismissal,
            // with no Cancel button in their actual navigation hierarchy.
            let start = pickerBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.pickerBar.exists }, object: app)
        guard XCTWaiter.wait(for: [dismissed], timeout: 10) == .completed else { throw SelectionError.cancellationNotCompleted }
    }
    private func confirm(_ labels: [String]) throws {
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        guard button.waitForExistence(timeout: 10), button.isEnabled else { throw SelectionError.confirmationNotFound }
        button.tap()
    }
}
