import UIKit

@MainActor
final class RemToastView: UIView {
    enum Kind {
        case success
        case info
        case empty
        case error

        var assetName: String {
            switch self {
            case .success: return "rem_in_bookshelf"
            case .info: return "rem_reader_resume"
            case .empty: return "rem_empty"
            case .error: return "rem_error"
            }
        }
    }

    private static weak var currentToast: RemToastView?
    private var dismissTask: Task<Void, Never>?
    private var actionHandler: (() -> Void)?

    private let illustration = UIImageView()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    private init(message: String, kind: Kind, actionTitle: String?, onAction: (() -> Void)?) {
        self.actionHandler = onAction
        super.init(frame: .zero)
        setupView(message: message, kind: kind, actionTitle: actionTitle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupView(message: String, kind: Kind, actionTitle: String?) {
        backgroundColor = Palette.card
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = Palette.border.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "rem.toast.banner"

        illustration.image = UIImage(named: kind.assetName)
        illustration.contentMode = .scaleAspectFit
        illustration.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = kind == .error ? Palette.danger : Palette.text
        messageLabel.numberOfLines = 2
        messageLabel.accessibilityIdentifier = "rem.toast.message"
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var arranged: [UIView] = [illustration, messageLabel]
        if let actionTitle, !actionTitle.isEmpty, actionHandler != nil {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            actionButton.setTitleColor(Palette.accent, for: .normal)
            actionButton.accessibilityIdentifier = "rem.toast.action"
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            actionButton.setContentHuggingPriority(.required, for: .horizontal)
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            arranged.append(actionButton)
        }

        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            illustration.widthAnchor.constraint(equalToConstant: 32),
            illustration.heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, actionHandler != nil, actionButton.superview != nil else {
            return nil
        }
        let buttonPoint = convert(point, to: actionButton)
        if actionButton.bounds.insetBy(dx: -8, dy: -8).contains(buttonPoint) {
            return actionButton
        }
        return nil
    }

    @objc private func actionTapped() {
        let callback = actionHandler
        actionHandler = nil
        dismiss(animated: true)
        callback?()
    }

    func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        if Self.currentToast === self {
            Self.currentToast = nil
        }
        guard superview != nil else { return }
        if animated {
            UIView.animate(withDuration: 0.18, animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: 12)
            }, completion: { _ in
                self.removeFromSuperview()
            })
        } else {
            removeFromSuperview()
        }
    }

    private static func resolveHostWindow(explicitWindow: UIWindow?, presenter: UIViewController?) -> UIWindow? {
        if let explicitWindow { return explicitWindow }
        if let presenterWindow = presenter?.viewIfLoaded?.window { return presenterWindow }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let allWindows = scenes.flatMap(\.windows)
        if let key = allWindows.first(where: \.isKeyWindow) { return key }
        return allWindows.first
    }

    @discardableResult
    static func show(
        message: String,
        kind: Kind = .info,
        actionTitle: String? = nil,
        duration: TimeInterval? = nil,
        in presenter: UIViewController? = nil,
        window explicitWindow: UIWindow? = nil,
        onAction: (() -> Void)? = nil
    ) -> RemToastView? {
        guard let window = resolveHostWindow(explicitWindow: explicitWindow, presenter: presenter) else { return nil }

        currentToast?.dismiss(animated: false)

        let toast = RemToastView(message: message, kind: kind, actionTitle: actionTitle, onAction: onAction)
        currentToast = toast
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12)
        window.addSubview(toast)

        let widthFill = toast.widthAnchor.constraint(equalTo: window.safeAreaLayoutGuide.widthAnchor, constant: -24)
        widthFill.priority = .defaultHigh
        let bottomOffset: CGFloat = -96

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.safeAreaLayoutGuide.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            widthFill,
            toast.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: bottomOffset)
        ])

        let skipAnimation: Bool
        #if DEBUG
        skipAnimation = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        skipAnimation = false
        #endif

        if skipAnimation {
            toast.alpha = 1
            toast.transform = .identity
        } else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                toast.alpha = 1
                toast.transform = .identity
            }
        }

        let effectiveDuration = duration ?? (onAction != nil ? 4.5 : 2.2)
        toast.dismissTask = Task { [weak toast] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, effectiveDuration) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            toast?.dismiss(animated: true)
        }
        return toast
    }
}
