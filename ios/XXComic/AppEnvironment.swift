import UIKit
import ComicCore

@MainActor
final class AppEnvironment {
    let preferences: ReaderPreferencesStore
    let defaults: UserDefaults
    let library: LibraryStore
    let localLibrary: LocalLibrary
    private let localSource: LocalComicSource
    let sources: [any ComicSource] = [GmhComicSource()]
    static let libraryChanged = Notification.Name("XXComic.libraryChanged")

    init(defaults: UserDefaults) throws {
        self.defaults = defaults
        preferences = ReaderPreferencesStore(defaults: defaults)
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
        library = try LibraryStore(directory: base.appendingPathComponent(suffix, isDirectory: true))
        localLibrary = try LocalLibrary(directory: base.appendingPathComponent(suffix, isDirectory: true).appendingPathComponent("Local", isDirectory: true))
        localSource = LocalComicSource(library: localLibrary)
    }

    func source(for comic: ComicSummary) -> (any ComicSource)? { comic.sourceId == "local" ? localSource : sources.first { $0.id == comic.sourceId } }
    func notifyLibraryChanged() { NotificationCenter.default.post(name: Self.libraryChanged, object: nil) }
}

extension UIViewController {
    func showError(_ error: Error) {
        guard !(error is CancellationError), presentedViewController == nil else { return }
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
