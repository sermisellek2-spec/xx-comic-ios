import UIKit

final class ReaderChromeGradientView: UIView {
    enum Edge { case top, bottom }
    private let edge: Edge
    override class var layerClass: AnyClass { CAGradientLayer.self }
    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }
    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let base = dark ? UIColor(red: 12/255, green: 20/255, blue: 32/255, alpha: 1)
            : UIColor(red: 247/255, green: 249/255, blue: 252/255, alpha: 1)
        let opaque: CGFloat = edge == .top && dark ? 240/255 : 242/255
        let faded = base.withAlphaComponent(216/255).cgColor
        let solid = base.withAlphaComponent(opaque).cgColor
        (layer as? CAGradientLayer)?.colors = edge == .top ? [solid, faded] : [faded, solid]
    }
}

final class ReaderOverlayBadge: UILabel {
    private let padding = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 12)
        numberOfLines = 1; lineBreakMode = .byTruncatingTail
        layer.cornerRadius = 12; layer.masksToBounds = true
        accessibilityIdentifier = "reader.status"
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: padding)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + padding.left + padding.right, height: size.height + padding.top + padding.bottom)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); updateColors()
    }
    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        textColor = dark ? UIColor(red: 230/255, green: 240/255, blue: 1, alpha: 220/255)
            : UIColor(red: 31/255, green: 35/255, blue: 40/255, alpha: 230/255)
        backgroundColor = dark ? UIColor(red: 12/255, green: 19/255, blue: 28/255, alpha: 140/255)
            : UIColor.white.withAlphaComponent(200/255)
        layer.borderColor = UIColor.black.withAlphaComponent(dark ? 0 : 40/255).cgColor
        layer.borderWidth = dark ? 0 : 1 / max(1, traitCollection.displayScale)
    }
}

final class ReaderContinuationFooter: UICollectionReusableView {
    private let button = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var onRetry: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        button.titleLabel?.font = .systemFont(ofSize: 12)
        button.titleLabel?.numberOfLines = 2
        button.accessibilityIdentifier = "reader.continuation"
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, button])
        stack.alignment = .center; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func configure(text: String, loading: Bool, canRetry: Bool, onRetry: (() -> Void)?) {
        self.onRetry = onRetry
        button.setTitle(text, for: .normal); button.isEnabled = canRetry
        button.tintColor = canRetry ? .systemBlue : .secondaryLabel
        spinner.isHidden = !loading
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
    @objc private func retry() { onRetry?() }
}
