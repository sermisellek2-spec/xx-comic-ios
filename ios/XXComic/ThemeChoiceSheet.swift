import UIKit
import ComicCore

@MainActor
final class ThemeChoiceSheet: UIViewController {
    private let selected: AppTheme
    private let onSelect: (AppTheme) -> Void

    init(selected: AppTheme, onSelect: @escaping (AppTheme) -> Void) {
        self.selected = selected; self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("theme")) { _ in 218 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.card
        let heading = UILabel(); heading.text = "选择主题"; heading.textColor = Palette.text
        heading.font = .systemFont(ofSize: 17, weight: .medium)
        let close = UIButton(type: .system); close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Palette.accent
        close.accessibilityLabel = "关闭"; close.accessibilityIdentifier = "theme.close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [heading, close]); header.alignment = .center
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let choices = UIStackView(); choices.spacing = 6; choices.distribution = .fillEqually
        let options: [(AppTheme, String, ParityIcon)] = [(.automatic, "跟随系统", .automatic), (.light, "浅色", .sun), (.dark, "深色", .moon)]
        for (theme, title, icon) in options {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = title; config.image = icon.image(size: 26)
            config.imagePlacement = .top; config.imagePadding = 12
            config.baseForegroundColor = theme == selected ? Palette.accent : Palette.text
            config.background.backgroundColor = theme == selected ? Palette.accentSoft : Palette.cardSoft
            config.background.cornerRadius = 10
            config.background.strokeColor = theme == selected ? Palette.accent : Palette.borderSoft
            config.background.strokeWidth = 1
            button.configuration = config
            button.isSelected = theme == selected
            button.accessibilityIdentifier = "theme.\(theme.rawValue)"
            if theme == selected { button.accessibilityTraits.insert(.selected) }
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                let apply = self.onSelect
                self.dismiss(animated: true) { apply(theme) }
            }, for: .touchUpInside)
            choices.addArrangedSubview(button)
        }
        let content = UIStackView(arrangedSubviews: [header, choices]); content.axis = .vertical; content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            choices.heightAnchor.constraint(equalToConstant: 108)
        ])
    }
}
