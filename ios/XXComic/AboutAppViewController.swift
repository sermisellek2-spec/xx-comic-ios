import UIKit
import ComicCore

@MainActor
final class AboutAppViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let environment: AppEnvironment

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = UIView()

    private static let appIntroText =
        "XX Comic 是一款集多站源搜索、在线阅读与本地漫画管理于一体的阅读工具，支持本地文件导入、离线下载、书架收藏与阅读历史。\n\n"
        + "提供条漫与单页阅读模式，以及阅读主题、翻页方式等个性化设置，让你按照自己的习惯轻松阅读。书架、阅读记录与设置保存在本机。"

    private static let disclaimerText =
        "1. 本应用提供漫画检索、浏览与本地文件阅读功能。在线内容来自对应第三方站点，本地内容由用户自行导入，相关作品的著作权归原作者及权利人所有。\n\n"
        + "2. 本应用不直接存储或制作第三方在线内容，也不控制第三方站点的页面、服务、更新及可访问性。第三方链接、搜索结果和页面内容仅供用户自行查看和判断，不代表本应用认可其内容、观点或合法性。\n\n"
        + "3. 请遵守适用法律法规及相关站点的使用规则，仅导入、阅读、下载或保存你有权使用的内容，尊重知识产权及其他合法权益，不得未经授权复制、传播、出售或用于其他侵权用途。\n\n"
        + "4. 用户应自行确认所访问、导入和下载内容的适宜性与安全性，并对自己的使用行为及由此产生的后果负责。未成年人应在监护人指导下使用本应用，避免接触不适宜内容。\n\n"
        + "5. 因网络环境、设备系统、地区限制、第三方站点调整、访问策略、服务中断或其他不可归责于本应用的原因，可能导致内容无法加载、显示不完整、链接失效或服务暂时不可用。本应用不保证第三方内容的准确性、完整性、及时性或持续可用性。\n\n"
        + "6. 本地导入文件、离线漫画、书架信息和阅读记录请自行妥善保管和备份。卸载应用、清除应用数据、删除本地文件或系统清理可能导致相关数据丢失，具体以文件保存位置和设备系统行为为准。\n\n"
        + "7. 如发现相关内容涉嫌侵犯著作权或其他合法权益，请通过应用内反馈渠道（如有）或向相关内容提供方提交权利证明及具体链接。本应用将在法律允许和技术可行的范围内配合处理。\n\n"
        + "8. 继续使用本应用即表示你已阅读并理解本声明。若你不同意其中内容，请停止使用相关功能。本声明不排除或限制法律法规规定不得排除或限制的责任。\n\n"
        + "最后更新：2026 年 9 月 22 日"

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.56"
        SecondaryHeaderBar.apply(to: self, title: "关于 App", meta: shortVersion)
        view.backgroundColor = Palette.background

        setupHeader()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SecondaryHeaderBar.configureNavigationBarAppearance(for: navigationController)
    }

    private func setupHeader() {
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 170)

        let mark = UIImageView()
        AppIllustrationCache.bind(mark, assetName: "rem_reader_resume", maxSideDp: 72)
        mark.contentMode = .scaleAspectFill
        mark.layer.cornerRadius = 16
        mark.clipsToBounds = true
        mark.backgroundColor = Palette.accentSoft
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
        tableView.separatorColor = Palette.borderSoft
        tableView.tableHeaderView = headerView
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
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
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["本地信息", "应用介绍", "免责声明"][section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.backgroundColor = Palette.card
            cell.selectionStyle = .none
            cell.textLabel?.textColor = Palette.text
            cell.textLabel?.font = .systemFont(ofSize: 14)
            cell.detailTextLabel?.textColor = Palette.secondaryText
            cell.detailTextLabel?.font = .systemFont(ofSize: 12)

            if indexPath.row == 0 {
                cell.textLabel?.text = "版本"
                let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.56"
                let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "356"
                cell.detailTextLabel?.text = "\(shortVersion) (\(buildVersion))"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "数据说明"
                cell.detailTextLabel?.text = "仅本地"
            } else {
                cell.textLabel?.text = "已接入站源"
                let installedIDs = Set(environment.sourcePreferences.availableIDs).subtracting(BuiltinSourceCatalog.retiredIDs)
                cell.detailTextLabel?.text = "\(environment.allSources.filter { installedIDs.contains($0.id) }.count) 个"
            }
            return cell
        }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Palette.card
        cell.selectionStyle = .none
        let body = UILabel()
        body.font = .systemFont(ofSize: 14)
        body.textColor = Palette.text2
        body.numberOfLines = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let copy = indexPath.section == 1 ? Self.appIntroText : Self.disclaimerText
        body.attributedText = NSAttributedString(string: copy, attributes: [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: Palette.text2,
            .paragraphStyle: paragraph
        ])
        body.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            body.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
            body.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -14)
        ])
        return cell
    }
}
