import UIKit
import ComicCore

@MainActor
final class AppEnvironment {
    let preferences: ReaderPreferencesStore
    let defaults: UserDefaults
    let readingHabits: ReadingHabitTracker
    let library: LibraryStore
    let localLibrary: LocalLibrary
    private let localSource: LocalComicSource
    let allSources: [any ComicSource]
    let sourcePreferences: SourcePreferences
    var sources: [any ComicSource] { sourcePreferences.enabledIDs.compactMap { id in allSources.first { $0.id == id } } }
    static let libraryChanged = Notification.Name("XXComic.libraryChanged")
    static let sourcesChanged = Notification.Name("XXComic.sourcesChanged")

    init(defaults: UserDefaults) throws {
        self.defaults = defaults
        let available: [any ComicSource] = [BaoziComicSource(), Mh160ComicSource(), GmhComicSource(), MkzhanComicSource(), HiperdexComicSource(), D5d6ComicSource(), FiveUmComicSource(), FiveUmComicSource(site: .bbyin), AntbywComicSource()]
        allSources = available
        sourcePreferences = SourcePreferences(defaults: defaults, defaultIDs: available.map(\.id))
        preferences = ReaderPreferencesStore(defaults: defaults)
        let habits = ReadingHabitTracker()
        habits.restore(from: defaults)
        readingHabits = habits
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let suffix = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "XXComic-UITests" : "XXComic"
        library = try LibraryStore(directory: base.appendingPathComponent(suffix, isDirectory: true))
        localLibrary = try LocalLibrary(directory: base.appendingPathComponent(suffix, isDirectory: true).appendingPathComponent("Local", isDirectory: true))
        localSource = LocalComicSource(library: localLibrary)
        habits.onChange = { [weak habits, weak defaults] in
            guard let habits, let defaults else { return }
            habits.save(to: defaults)
        }
    }

    func source(for comic: ComicSummary) -> (any ComicSource)? { comic.sourceId == "local" ? localSource : allSources.first { $0.id == comic.sourceId } }
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
