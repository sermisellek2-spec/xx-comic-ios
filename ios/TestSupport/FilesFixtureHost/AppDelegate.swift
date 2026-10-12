import UIKit

/// A separate simulator-only fixture app. Its shared Documents directory is
/// outside XXComic's sandbox; XXComic must use the real Files chooser and grant.
@main
final class FilesFixtureAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = FilesFixtureViewController()
        window.makeKeyAndVisible(); self.window = window
        return true
    }
}

private final class FilesFixtureViewController: UIViewController {
    private let status = UILabel()
    private var selected: URL?
    private var replacement: URL?
    private let markerName = ".fixture-owner"
    private var token: String?
    private var configFolder: URL?
    private let exportStatus = UILabel()
    private let downloadStatus = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        status.numberOfLines = 0; status.accessibilityIdentifier = "files.fixture.status"
        let retire = UIButton(type: .system)
        retire.setTitle("模拟原目录失效，保留新目录", for: .normal)
        retire.accessibilityIdentifier = "files.fixture.retire"
        retire.addTarget(self, action: #selector(retireFolder), for: .touchUpInside)
        let verify = UIButton(type: .system)
        verify.setTitle("校验实际导出的站源文件", for: .normal)
        verify.accessibilityIdentifier = "files.fixture.verify-export"
        verify.addTarget(self, action: #selector(verifyExport), for: .touchUpInside)
        exportStatus.numberOfLines = 0; exportStatus.accessibilityIdentifier = "files.fixture.export.status"
        let verifyDownload = UIButton(type: .system)
        verifyDownload.setTitle("校验外部目录的下载像素", for: .normal)
        verifyDownload.accessibilityIdentifier = "files.fixture.verify-download"
        verifyDownload.addTarget(self, action: #selector(verifyDownloadedPixels), for: .touchUpInside)
        downloadStatus.numberOfLines = 0; downloadStatus.accessibilityIdentifier = "files.fixture.download.status"
        let stack = UIStackView(arrangedSubviews: [status, retire, verify, exportStatus, verifyDownload, downloadStatus])
        stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        do {
            guard let session = ProcessInfo.processInfo.environment["FILES_FIXTURE_SESSION"], UUID(uuidString: session) != nil else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            token = session
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = documents.appendingPathComponent("Files漫画_" + String(session.prefix(8)), isDirectory: true)
            selected = folder; replacement = documents.appendingPathComponent(folder.lastPathComponent + "_新", isDirectory: true)
            try create(folder, session: session)
            let configs = documents.appendingPathComponent("站源配置_" + String(session.prefix(8)), isDirectory: true)
            try createConfigs(configs); configFolder = configs
            status.text = "准备完成：" + folder.lastPathComponent
        } catch { status.text = "准备失败：" + error.localizedDescription }
    }

    private func createConfigs(_ folder: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) { return }
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        let files = [
            "changed.json": #"{"schema":"xx-comic.sources","version":2,"sourceOrder":["duya","mh160"],"sources":[{"id":"duya","enabled":true},{"id":"mh160","enabled":false}]}"#,
            "invalid.json": #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"mh160","enabled":false},{"id":"gmh","enabled":"invalid"}]}"#,
            "partial.json": #"{"schema":"xx-comic.sources","version":2,"sources":[{"id":"gmh","enabled":false,"routes":{"fictional":"/ignored"}},{"id":"baozimh"}],"custom":[{"id":"custom-test"}]}"#
        ]
        for (name, text) in files { try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .withoutOverwriting) }
    }

    @objc private func verifyExport() {
        do {
            guard let configFolder else { throw CocoaError(.fileNoSuchFile) }
            let data = try Data(contentsOf: configFolder.appendingPathComponent("xx-comic-sources.json"))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["schema"] as? String == "xx-comic.sources", json["version"] as? Int == 2,
                  let sources = json["sources"] as? [[String: Any]], sources.count == 51,
                  Set(sources.compactMap { $0["id"] as? String }).count == 51,
                  sources.first(where: { $0["id"] as? String == "duya" })?["enabled"] as? Bool == true,
                  sources.first(where: { $0["id"] as? String == "mh160" })?["enabled"] as? Bool == false,
                  let order = json["sourceOrder"] as? [String], order.count == 51, Array(order.prefix(2)) == ["duya", "mh160"] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let enabled = sources.filter { $0["enabled"] as? Bool == true }.count
            exportStatus.text = "已校验实际文件：51 个站源，\(enabled) 个开启；毒牙开启，漫画160关闭"
        } catch { exportStatus.text = "导出文件校验失败" }
    }

    @objc private func verifyDownloadedPixels() {
        guard let selected, let token else { return }
        downloadStatus.text = "正在检查外部目录下载副本…"
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    let manager = FileManager.default
                    let info = try selected.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard info.isDirectory == true, info.isSymbolicLink != true,
                          try Data(contentsOf: selected.appendingPathComponent(".fixture-owner")) == Data(token.utf8),
                          let original1 = UIImage(contentsOfFile: selected.appendingPathComponent("01.png").path),
                          let original2 = UIImage(contentsOfFile: selected.appendingPathComponent("02.png").path),
                          original1.size == CGSize(width: 32, height: 48), original2.size == original1.size else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let root = selected.appendingPathComponent("XXComic/downloads", isDirectory: true)
                    guard let entries = manager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                        throw CocoaError(.fileReadNoSuchFile)
                    }
                    var scanned = 0, found = false
                    for case let file as URL in entries {
                        scanned += 1
                        guard scanned <= 4096 else { throw CocoaError(.fileReadTooLarge) }
                        let properties = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                        guard properties.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
                        if file.pathExtension == "img", properties.isRegularFile == true,
                           (properties.fileSize ?? 0) <= 1024 * 1024,
                           let image = UIImage(contentsOfFile: file.path), image.size == CGSize(width: 384, height: 384) { found = true }
                    }
                    guard found else { throw CocoaError(.fileReadCorruptFile) }
                }.value
                self?.downloadStatus.text = "已校验外部目录下载像素：384×384，原文件保留"
            } catch { self?.downloadStatus.text = "外部下载副本校验失败" }
        }
    }

    private func image(_ index: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48), format: format).image {
            (index == 1 ? UIColor.systemBlue : UIColor.systemRed).setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        }.pngData()!
    }
    private func create(_ folder: URL, session: String) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) { return }
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data(session.utf8).write(to: folder.appendingPathComponent(markerName), options: .withoutOverwriting)
        for index in 1...2 { try image(index).write(to: folder.appendingPathComponent("0\(index).png"), options: .withoutOverwriting) }
    }

    @objc private func retireFolder() {
        do {
            guard let selected, let replacement, let token,
                  selected.deletingLastPathComponent() == replacement.deletingLastPathComponent() else { throw CocoaError(.fileNoSuchFile) }
            let manager = FileManager.default
            let folderInfo = try selected.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard folderInfo.isDirectory == true, folderInfo.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
            let names = Set(try manager.contentsOfDirectory(atPath: selected.path))
            guard names == [markerName, "01.png", "02.png"],
                  try Data(contentsOf: selected.appendingPathComponent(markerName)) == Data(token.utf8) else { throw CocoaError(.fileReadNoPermission) }
            // Only the three generated objects are removed; any unknown entry
            // causes refusal. There is no recursive fixture-directory deletion.
            for name in names {
                let file = selected.appendingPathComponent(name)
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
            }
            try create(replacement, session: token)
            for name in names { try manager.removeItem(at: selected.appendingPathComponent(name)) }
            guard try manager.contentsOfDirectory(atPath: selected.path).isEmpty else { throw CocoaError(.fileWriteNoPermission) }
            try manager.removeItem(at: selected)
            status.text = "原目录已失效；新目录：" + replacement.lastPathComponent
        } catch { status.text = "失效模拟失败：" + error.localizedDescription }
    }
}
