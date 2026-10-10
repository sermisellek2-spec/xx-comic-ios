import UIKit
import ComicCore

@MainActor
final class AboutAppViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = UIView()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "关于 App"
        view.backgroundColor = Palette.background

        setupHeader()
        setupTableView()
    }

    private func setupHeader() {
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 180)

        let mark = UIImageView()
        mark.image = UIImage(named: "rem_reader_resume")
        mark.contentMode = .scaleAspectFill
        mark.layer.cornerRadius = 16
        mark.clipsToBounds = true
        mark.backgroundColor = Palette.card
        mark.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(mark)

        let titleLabel = UILabel()
        titleLabel.text = "XX Comic"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = "多站源漫画浏览与本地阅读工具\n收藏、历史和设置均保存在本机"
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = Palette.secondaryText
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 2
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(descLabel)

        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            mark.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            mark.widthAnchor.constraint(equalToConstant: 68),
            mark.heightAnchor.constraint(equalToConstant: 68),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 8),

            descLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Palette.background
        tableView.tableHeaderView = headerView
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "本地信息"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.selectionStyle = .none
        cell.textLabel?.textColor = Palette.text
        cell.textLabel?.font = .systemFont(ofSize: 14)
        cell.detailTextLabel?.textColor = Palette.secondaryText
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)

        if indexPath.row == 0 {
            cell.textLabel?.text = "版本"
            let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.40"
            let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "340"
            cell.detailTextLabel?.text = "\(shortVersion) (\(buildVersion))"
        } else if indexPath.row == 1 {
            cell.textLabel?.text = "数据说明"
            cell.detailTextLabel?.text = "仅本地"
        } else {
            cell.textLabel?.text = "已接入站源"
            cell.detailTextLabel?.text = "\(environment.allSources.count) 个"
        }
        return cell
    }
}
