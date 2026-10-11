import UIKit

/// Android's two text tabs share the header; there is no extra segmented row.
@MainActor
final class BookshelfTabsView: UIControl {
    private let buttons = [UIButton(type: .system), UIButton(type: .system)]
    private let divider = UILabel()
    var selectedSegmentIndex = 0 { didSet { updateSelection() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElements = buttons
        divider.text = " | "; divider.textColor = Palette.text3; divider.font = .systemFont(ofSize: 16)
        divider.isAccessibilityElement = false
        for (index, button) in buttons.enumerated() {
            button.setTitle(index == 0 ? "我的书架" : "本地书架", for: .normal)
            button.tag = index; button.accessibilityIdentifier = "bookshelf.tab.\(index)"
            button.isAccessibilityElement = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(selectTab(_:)), for: .touchUpInside)
        }
        let row = UIStackView(arrangedSubviews: [buttons[0], divider, buttons[1]])
        row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor), heightAnchor.constraint(equalToConstant: 44)])
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: buttons.reduce(divider.intrinsicContentSize.width) { $0 + $1.intrinsicContentSize.width }, height: 44)
    }
    @objc private func selectTab(_ sender: UIButton) {
        guard selectedSegmentIndex != sender.tag else { return }
        selectedSegmentIndex = sender.tag; sendActions(for: .valueChanged)
    }
    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedSegmentIndex
            button.titleLabel?.font = .systemFont(ofSize: selected ? 24 : 16, weight: selected ? .bold : .regular)
            button.setTitleColor(selected ? Palette.text : Palette.text3, for: .normal)
            button.isSelected = selected
        }
        invalidateIntrinsicContentSize()
    }
}
