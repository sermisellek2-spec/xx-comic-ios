import UIKit

/// Android's two text tabs share the header; there is no extra segmented row.
@MainActor
final class BookshelfTabsView: UIControl {
    private var tabs: [UIBarButtonItem] = []
    private let divider = UILabel()
    private(set) var navigationItems: [UIBarButtonItem] = []
    var selectedSegmentIndex = 0 { didSet { updateSelection() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        divider.text = " | "; divider.textColor = Palette.text3; divider.font = .systemFont(ofSize: 16)
        divider.isAccessibilityElement = false
        // UINavigationBar exposes a composite custom control as one bar item.
        // Standard bar items give each tab its own accessible activation target.
        tabs = ["我的书架", "本地书架"].enumerated().map { index, title in
            let item = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(selectTab(_:)))
            item.tag = index
            item.accessibilityLabel = title
            item.accessibilityIdentifier = "bookshelf.tab.\(index)"
            item.isAccessibilityElement = true
            return item
        }
        divider.sizeToFit()
        let separator = UIBarButtonItem(customView: divider)
        separator.isAccessibilityElement = false
        navigationItems = [tabs[0], separator, tabs[1]]
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    @objc private func selectTab(_ sender: UIBarButtonItem) {
        guard selectedSegmentIndex != sender.tag else { return }
        selectedSegmentIndex = sender.tag; sendActions(for: .valueChanged)
    }
    private func updateSelection() {
        for (index, item) in tabs.enumerated() {
            let selected = index == selectedSegmentIndex
            item.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: selected ? 24 : 16, weight: selected ? .bold : .regular),
                .foregroundColor: selected ? Palette.text : Palette.text3], for: .normal)
            item.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}
