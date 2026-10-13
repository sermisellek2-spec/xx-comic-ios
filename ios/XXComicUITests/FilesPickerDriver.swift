import XCTest

/// Drive the system provider UI; no selected URL or permission is injected.
struct FilesPickerDriver {
    let app: XCUIApplication
    var capture: (String) -> Void = { _ in }
    private let localNames = ["我的 iPhone", "我的 iPad", "On My iPhone", "On My iPad", "在我的 iPhone 上", "在我的 iPad 上"]
    private enum SelectionError: Error { case providerNotFound, folderNotOpened, fileNotFound, confirmationNotFound, cancellationNotCompleted }

    private var pickerBar: XCUIElement { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"] }
    private var systemBars: XCUIElementQuery {
        app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'DocumentManager' OR identifier CONTAINS 'DOCSidebarView'"))
    }
    private var pickerRoot: XCUIElement {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'DOC.browsingRoot'")).firstMatch
    }

    private func isShowingFolder(_ name: String) -> Bool {
        pickerBar.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch.exists
            || pickerBar.staticTexts[name].exists || app.navigationBars[name].exists
    }

    func openFixtureProvider() throws {
        guard pickerBar.waitForExistence(timeout: 10) else { throw SelectionError.providerNotFound }
        capture("provider-start")
        let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse"])).firstMatch
        let local = app.cells.containing(NSPredicate(format: "label IN %@", localNames)).firstMatch
        let back = systemBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse", "位置", "Locations", "返回", "Back"] + localNames)).firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["显示边栏", "Show Sidebar"])).firstMatch
        let provider = pickerRoot.cells.containing(.staticText, identifier: "XXComic Files Fixture").firstMatch
        let parent = systemBars.buttons.matching(NSPredicate(format: "label IN %@", ["XXComic Files Fixture"])).firstMatch
        var selectedBrowse = false
        for _ in 0..<10 {
            if isShowingFolder("XXComic Files Fixture") { capture("provider-root"); return }
            if provider.exists && provider.isHittable {
                try openFolder("XXComic Files Fixture")
                capture("provider-root"); return
            }
            if local.exists && local.isHittable { local.tap() }
            else if parent.exists && parent.isHittable { parent.tap() }
            else if back.exists && back.isHittable { back.tap() }
            else if sidebar.exists && sidebar.isHittable { sidebar.tap() }
            else if browse.exists && browse.isHittable && !selectedBrowse { browse.tap(); selectedBrowse = true }
            else {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    self.isShowingFolder("XXComic Files Fixture") || provider.isHittable || local.isHittable || parent.isHittable || back.isHittable || sidebar.isHittable
                }, object: app)
                if XCTWaiter.wait(for: [ready], timeout: 3) != .completed { break }
            }
        }
        throw SelectionError.providerNotFound
    }

    func openFolder(_ name: String) throws {
        let cell = pickerRoot.cells.containing(.staticText, identifier: name).firstMatch
        if !cell.waitForExistence(timeout: 2) || !cell.isHittable {
            let collection = pickerRoot.collectionViews.firstMatch
            let scrollView = collection.exists ? collection : pickerRoot
            for _ in 0..<8 where !cell.exists || !cell.isHittable {
                scrollView.swipeUp()
            }
            for _ in 0..<8 where !cell.exists || !cell.isHittable {
                scrollView.swipeDown()
            }
        }
        guard cell.waitForExistence(timeout: 5), cell.isHittable else { throw SelectionError.folderNotOpened }
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
        let file = pickerRoot.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", name, stem)).firstMatch
        if !file.waitForExistence(timeout: 2) || !file.isHittable {
            let collection = pickerRoot.collectionViews.firstMatch
            let scrollView = collection.exists ? collection : pickerRoot
            for _ in 0..<6 where !file.exists || !file.isHittable {
                scrollView.swipeUp()
            }
            for _ in 0..<6 where !file.exists || !file.isHittable {
                scrollView.swipeDown()
            }
        }
        guard file.waitForExistence(timeout: 5), file.isHittable else { throw SelectionError.fileNotFound }
        file.tap()
    }

    func confirmFolder() throws { try confirm(["打开", "Open", "完成", "Done"]) }
    func confirmExport() throws { try confirm(["导出", "存储", "保存", "拷贝", "移动", "Export", "Save", "Copy", "Move"]) }
    func cancelPicker() throws {
        guard pickerBar.waitForExistence(timeout: 15) else { throw SelectionError.providerNotFound }
        // iPad's Cancel is in DOCSidebarView's navigation bar, while the
        // folder title lives in FullDocumentManagerViewControllerNavigationBar.
        let cancel = systemBars.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
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
        guard pickerBar.waitForExistence(timeout: 10) else { throw SelectionError.providerNotFound }
        let button = systemBars.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: button)
        guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed else { throw SelectionError.confirmationNotFound }
        button.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.pickerBar.exists }, object: app)
        guard XCTWaiter.wait(for: [dismissed], timeout: 10) == .completed else { throw SelectionError.confirmationNotFound }
    }
}
