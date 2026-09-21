import UIKit
import ComicCore

@MainActor
final class BatchImportConfirmationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    public typealias ConfirmationHandler = ([BatchImportGroup], [String: URL]) -> Void

    private let initialCandidates: [BatchImportCandidate]
    private let urlMap: [String: URL]
    private let onConfirm: ConfirmationHandler

    private var groups: [BatchImportGroup] = []
    private var isMergedIntoSingleSeries: Bool = false
    private var mergedSeriesTitle: String = ""

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let mergeSwitchContainer = UIView()
    private let mergeSwitchLabel = UILabel()
    private let mergeSwitch = UISwitch()
    private let confirmButton = UIButton(type: .system)

    init(candidates: [BatchImportCandidate],
         urlMap: [String: URL],
         onConfirm: @escaping ConfirmationHandler) {
        self.initialCandidates = candidates
        self.urlMap = urlMap
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        recomputeGroups()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSheet()
        view.backgroundColor = Palette.background
        title = "批量导入确认"

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))

        setupViews()
    }

    private func setupSheet() {
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                if #available(iOS 16.0, *) {
                    let customDetent = UISheetPresentationController.Detent.custom(identifier: .init("72percent")) { context in
                        return context.maximumDetentValue * 0.72
                    }
                    sheet.detents = [customDetent, .large()]
                } else {
                    sheet.detents = [.medium(), .large()]
                }
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }
        }
    }

    private func setupViews() {
        // Merge switch row
        mergeSwitchContainer.translatesAutoresizingMaskIntoConstraints = false
        mergeSwitchContainer.backgroundColor = Palette.card
        mergeSwitchContainer.layer.cornerRadius = 10
        view.addSubview(mergeSwitchContainer)

        mergeSwitchLabel.translatesAutoresizingMaskIntoConstraints = false
        mergeSwitchLabel.text = "合并为一部完整漫画"
        mergeSwitchLabel.font = .preferredFont(forTextStyle: .body)
        mergeSwitchLabel.textColor = Palette.text
        mergeSwitchContainer.addSubview(mergeSwitchLabel)

        mergeSwitch.translatesAutoresizingMaskIntoConstraints = false
        mergeSwitch.isOn = isMergedIntoSingleSeries
        mergeSwitch.addTarget(self, action: #selector(mergeSwitchChanged(_:)), for: .valueChanged)
        mergeSwitchContainer.addSubview(mergeSwitch)

        // Table view
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        // Confirm button
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle("确认导入 (\(initialCandidates.count) 卷)", for: .normal)
        confirmButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        confirmButton.backgroundColor = Palette.accent
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.layer.cornerRadius = 12
        confirmButton.clipsToBounds = true
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        view.addSubview(confirmButton)

        NSLayoutConstraint.activate([
            mergeSwitchContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            mergeSwitchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mergeSwitchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mergeSwitchContainer.heightAnchor.constraint(equalToConstant: 48),

            mergeSwitchLabel.leadingAnchor.constraint(equalTo: mergeSwitchContainer.leadingAnchor, constant: 16),
            mergeSwitchLabel.centerYAnchor.constraint(equalTo: mergeSwitchContainer.centerYAnchor),

            mergeSwitch.trailingAnchor.constraint(equalTo: mergeSwitchContainer.trailingAnchor, constant: -16),
            mergeSwitch.centerYAnchor.constraint(equalTo: mergeSwitchContainer.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: mergeSwitchContainer.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -12),

            confirmButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            confirmButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func recomputeGroups() {
        if isMergedIntoSingleSeries {
            let title = mergedSeriesTitle.isEmpty
                ? (initialCandidates.first.map { BatchImportPlanner.normalizeTitle($0.fileName) } ?? "合集漫画")
                : mergedSeriesTitle
            let ordered = BatchImportPlanner.orderVolumes(initialCandidates)
            groups = [BatchImportGroup(key: "merged:single", title: title, requiresConfirmation: false, volumes: ordered)]
        } else {
            groups = BatchImportPlanner.plan(initialCandidates)
        }
    }

    @objc private func mergeSwitchChanged(_ sender: UISwitch) {
        isMergedIntoSingleSeries = sender.isOn
        recomputeGroups()
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func confirmTapped() {
        let finalGroups = groups
        let finalUrlMap = urlMap
        dismiss(animated: true) { [onConfirm] in
            onConfirm(finalGroups, finalUrlMap)
        }
    }

    // MARK: - Table View

    func numberOfSections(in tableView: UITableView) -> Int {
        return groups.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return groups[section].volumes.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let group = groups[section]
        return "作品：\(group.title) (\(group.volumes.count) 卷)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CandidateCell") ??
            UITableViewCell(style: .subtitle, reuseIdentifier: "CandidateCell")
        let item = groups[indexPath.section].volumes[indexPath.row]
        cell.textLabel?.text = "第 \(indexPath.row + 1) 卷 · \(item.fileName)"
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.text = "格式：\(item.format.uppercased())"
        cell.detailTextLabel?.textColor = Palette.secondaryText
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Allow renaming the group when tapping section or item
        let section = indexPath.section
        let currentTitle = groups[section].title

        let alert = UIAlertController(title: "修改作品名称", message: "修改该作品合集的展示名称", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentTitle
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self, let newTitle = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !newTitle.isEmpty else { return }
            let oldGroup = self.groups[section]
            self.groups[section] = BatchImportGroup(key: oldGroup.key, title: newTitle, requiresConfirmation: oldGroup.requiresConfirmation, volumes: oldGroup.volumes)
            if self.isMergedIntoSingleSeries {
                self.mergedSeriesTitle = newTitle
            }
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
