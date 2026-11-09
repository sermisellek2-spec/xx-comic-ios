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
    private var providerCell: XCUIElement {
        (pickerRoot.exists ? pickerRoot : app).cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", "XXComic Files Fixture", "XXComic Files Fixture")).firstMatch
    }

    private func isShowingFolder(_ name: String) -> Bool {
        if pickerBar.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch.exists
            || pickerBar.staticTexts[name].exists
            || app.navigationBars[name].exists {
            return true
        }
        let anyFolderMenu = pickerBar.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).firstMatch
        if anyFolderMenu.exists || pickerBar.staticTexts.firstMatch.exists {
            return false
        }
        return pickerRoot.exists && pickerRoot.identifier.contains("Title: " + name)
    }

    private func waitForProviderOrFixtureRoot(timeout: TimeInterval) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.isShowingFolder("XXComic Files Fixture") || (self.providerCell.exists && self.providerCell.isHittable)
        }, object: app)
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed
    }

    func openFixtureProvider() throws {
        guard pickerBar.waitForExistence(timeout: 35) else { throw SelectionError.providerNotFound }
        capture("provider-start")
        let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["浏览", "Browse"])).firstMatch
        let local = app.cells.containing(NSPredicate(format: "label IN %@", localNames)).firstMatch
        let recents = app.cells.matching(NSPredicate(format: "identifier == 'DOC.sidebar.item.Recents' OR label IN %@", ["最近项目", "Recents"])).firstMatch
        let navBack = systemBars.buttons.matching(NSPredicate(format: "(label IN %@ OR identifier == 'BackButton') AND identifier != 'DOC.navBarButton.backInHistory'", ["XXComic Files Fixture", "浏览", "Browse", "位置", "Locations", "返回", "Back"] + localNames)).firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["显示边栏", "Show Sidebar"])).firstMatch
        var browseTapCount = 0
        var tappedLocal = false
        for _ in 0..<12 {
            if isShowingFolder("XXComic Files Fixture") { capture("provider-root"); return }
            let provider = providerCell
            if provider.exists && provider.isHittable {
                try openFolder("XXComic Files Fixture")
                capture("provider-root"); return
            }
            if navBack.exists && navBack.isEnabled && navBack.isHittable {
                if isShowingFolder("XXComic Files Fixture") || (providerCell.exists && providerCell.isHittable) { continue }
                navBack.tap()
                _ = waitForProviderOrFixtureRoot(timeout: 2.0)
            } else if local.exists && local.isHittable {
                if tappedLocal && recents.exists && recents.isHittable {
                    recents.tap()
                    tappedLocal = false
                    let switched = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        self.isShowingFolder("Recents") || self.isShowingFolder("最近项目")
                    }, object: app)
                    _ = XCTWaiter.wait(for: [switched], timeout: 1.5)
                } else {
                    local.tap()
                    tappedLocal = true
                    _ = waitForProviderOrFixtureRoot(timeout: 2.0)
                }
            } else if sidebar.exists && sidebar.isEnabled && sidebar.isHittable {
                sidebar.tap()
                let sidebarShown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in local.isHittable }, object: app)
                _ = XCTWaiter.wait(for: [sidebarShown], timeout: 1.5)
            } else if browse.exists && browse.isHittable && browseTapCount < 2 {
                browse.tap()
                browseTapCount += 1
                _ = waitForProviderOrFixtureRoot(timeout: 1.5)
            } else {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    self.isShowingFolder("XXComic Files Fixture") || self.providerCell.isHittable || local.isHittable || (navBack.isEnabled && navBack.isHittable) || sidebar.isHittable
                }, object: app)
                if XCTWaiter.wait(for: [ready], timeout: 3) != .completed { break }
            }
        }
        throw SelectionError.providerNotFound
    }

    func openFolder(_ name: String) throws {
        if isShowingFolder(name) { capture("target-folder"); return }
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", name, name)
        let root = pickerRoot.exists ? pickerRoot : app
        var cell = root.cells.matching(predicate).firstMatch
        if !cell.exists {
            cell = root.cells.containing(.staticText, identifier: name).firstMatch
        }
        if !cell.waitForExistence(timeout: 3) || !cell.isHittable {
            let collection = (pickerRoot.exists ? pickerRoot : app).collectionViews.firstMatch
            if collection.exists {
                var swipedUp = 0
                for _ in 0..<4 where !cell.exists || !cell.isHittable {
                    collection.swipeUp()
                    swipedUp += 1
                }
                for _ in 0..<swipedUp where !cell.exists || !cell.isHittable {
                    let start = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                    let end = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
            }
        }
        guard cell.waitForExistence(timeout: 5) else { throw SelectionError.folderNotOpened }
        let icon = cell.images.firstMatch
        if icon.exists && icon.isHittable {
            icon.doubleTap()
        } else {
            cell.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).doubleTap()
        }
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isShowingFolder(name) }, object: app)
        if XCTWaiter.wait(for: [opened], timeout: 10) != .completed {
            if icon.exists && icon.isHittable {
                icon.tap()
            } else if cell.exists && cell.isHittable {
                cell.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            }
            let retryOpened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isShowingFolder(name) }, object: app)
            guard XCTWaiter.wait(for: [retryOpened], timeout: 5) == .completed else { throw SelectionError.folderNotOpened }
        }
        capture("target-folder")
    }

    func selectFile(_ name: String) throws {
        let stem = (name as NSString).deletingPathExtension
        let root = pickerRoot.exists ? pickerRoot : app
        let file = root.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", name, stem)).firstMatch
        if !file.waitForExistence(timeout: 5) || !file.isHittable {
            let collection = (pickerRoot.exists ? pickerRoot : app).collectionViews.firstMatch
            if collection.exists {
                var swipedUp = 0
                for _ in 0..<4 where !file.exists || !file.isHittable {
                    collection.swipeUp()
                    swipedUp += 1
                }
                for _ in 0..<swipedUp where !file.exists || !file.isHittable {
                    let start = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                    let end = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
            }
        }
        guard file.waitForExistence(timeout: 5) else { throw SelectionError.fileNotFound }
        if file.isHittable {
            file.tap()
        } else {
            file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func confirmFolder() throws { try confirm(["打开", "Open", "完成", "Done"]) }
    func confirmExport() throws { try confirm(["导出", "存储", "保存", "拷贝", "移动", "Export", "Save", "Copy", "Move"]) }
    func cancelPicker() throws {
        guard pickerBar.waitForExistence(timeout: 35) else { throw SelectionError.providerNotFound }
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
        guard pickerBar.waitForExistence(timeout: 20) else { throw SelectionError.providerNotFound }
        let button = systemBars.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: button)
        guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed else { throw SelectionError.confirmationNotFound }
        button.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.pickerBar.exists }, object: app)
        guard XCTWaiter.wait(for: [dismissed], timeout: 10) == .completed else { throw SelectionError.confirmationNotFound }
    }
}
