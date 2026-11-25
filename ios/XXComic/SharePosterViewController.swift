import UIKit
import Photos
import ImageIO

/// Renders the bundled `share_poster.png` card with save-to-photos and system share sheet actions.
@MainActor
final class SharePosterViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let posterCard = UIView()
    private let posterImageView = UIImageView()
    private var posterAspectConstraint: NSLayoutConstraint?
    private var loadedPosterImage: UIImage?
    private var loadTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        SecondaryHeaderBar.apply(to: self, title: "分享 App", meta: "点击图片保存或分享")
        setupViews()
        loadPoster()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SecondaryHeaderBar.configureNavigationBarAppearance(for: navigationController)
    }

    deinit {
        loadTask?.cancel()
    }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        posterCard.backgroundColor = Palette.card
        posterCard.layer.cornerRadius = 16
        posterCard.layer.borderWidth = 1
        posterCard.layer.borderColor = Palette.borderSoft.cgColor
        posterCard.clipsToBounds = true
        posterCard.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(posterCard)

        posterImageView.contentMode = .scaleAspectFit
        posterImageView.isUserInteractionEnabled = true
        posterImageView.isAccessibilityElement = true
        posterImageView.accessibilityTraits = .button
        posterImageView.accessibilityLabel = "分享海报，点击保存或分享"
        posterImageView.accessibilityIdentifier = "share.poster.image"
        posterImageView.translatesAutoresizingMaskIntoConstraints = false
        posterImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(posterTapped)))
        posterCard.addSubview(posterImageView)

        let cardWidthFill = posterCard.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        cardWidthFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            posterCard.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            posterCard.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            posterCard.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            posterCard.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            posterCard.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            posterCard.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            cardWidthFill,

            posterImageView.topAnchor.constraint(equalTo: posterCard.topAnchor),
            posterImageView.leadingAnchor.constraint(equalTo: posterCard.leadingAnchor),
            posterImageView.trailingAnchor.constraint(equalTo: posterCard.trailingAnchor),
            posterImageView.bottomAnchor.constraint(equalTo: posterCard.bottomAnchor)
        ])
    }

    private func loadPoster() {
        loadTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let url = Bundle.main.url(forResource: "share_poster", withExtension: "png"),
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            }.value
            guard let self, !Task.isCancelled else { return }
            let image = decoded ?? UIImage(named: "share_poster")
            self.loadedPosterImage = image
            self.posterImageView.image = image
            if let image, image.size.width > 0, image.size.height > 0 {
                self.posterAspectConstraint?.isActive = false
                let aspect = self.posterImageView.heightAnchor.constraint(
                    equalTo: self.posterImageView.widthAnchor,
                    multiplier: image.size.height / image.size.width
                )
                aspect.isActive = true
                self.posterAspectConstraint = aspect
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        posterCard.layer.borderColor = Palette.borderSoft.resolvedColor(with: traitCollection).cgColor
    }

    @objc private func posterTapped() {
        let sheet = SharePosterActionsSheetController(
            onSaveToLibrary: { [weak self] in self?.savePosterToPhotoLibrary() },
            onShareImage: { [weak self] in self?.sharePosterImage() }
        )
        present(sheet, animated: false)
    }

    private func savePosterToPhotoLibrary() {
        guard let image = loadedPosterImage ?? posterImageView.image else {
            RemToastView.show(message: "无法读取分享海报资源", kind: .error, in: self)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized || status == .limited else {
                    let alert = UIAlertController(
                        title: "需要相册写入权限",
                        message: "请在系统设置中允许访问“照片”（仅添加），或选择“分享图片”保存。",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "知道了", style: .default))
                    self.present(alert, animated: true)
                    return
                }
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                    RemToastView.show(message: "已保存到系统相册", kind: .success, in: self)
                } catch {
                    RemToastView.show(message: "保存到相册失败，请稍后重试", kind: .error, in: self)
                }
            }
        }
    }

    private func sharePosterImage() {
        guard let image = loadedPosterImage ?? posterImageView.image else {
            RemToastView.show(message: "无法读取分享海报资源", kind: .error, in: self)
            return
        }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = posterCard
            popover.sourceRect = CGRect(x: posterCard.bounds.midX, y: posterCard.bounds.midY, width: 1, height: 1)
        }
        present(activityVC, animated: true)
    }
}

@MainActor
private final class SharePosterActionsSheetController: UIViewController {
    private let onSaveToLibrary: () -> Void
    private let onShareImage: () -> Void
    private let backdropView = UIView()
    private let panelView = UIView()
    private var panelBottomConstraint: NSLayoutConstraint!
    private var panelWidthConstraint: NSLayoutConstraint!
    private var isClosing = false

    init(onSaveToLibrary: @escaping () -> Void, onShareImage: @escaping () -> Void) {
        self.onSaveToLibrary = onSaveToLibrary
        self.onShareImage = onShareImage
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePanelWidth()
        panelBottomConstraint.constant = 0
        if UIAccessibility.isReduceMotionEnabled {
            backdropView.alpha = 1
            view.layoutIfNeeded()
        } else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                self.backdropView.alpha = 1
                self.view.layoutIfNeeded()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelWidth()
    }

    private func updatePanelWidth() {
        let maxW: CGFloat = traitCollection.horizontalSizeClass == .regular ? 520 : view.bounds.width
        panelWidthConstraint.constant = min(view.bounds.width, maxW)
    }

    private func setupUI() {
        backdropView.backgroundColor = Palette.scrim
        backdropView.alpha = 0
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        view.addSubview(backdropView)

        panelView.backgroundColor = Palette.card
        panelView.layer.cornerRadius = 16
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.clipsToBounds = true
        panelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelView)

        let titleLabel = UILabel()
        titleLabel.text = "保存与分享"
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center

        let saveRow = makeActionRow(icon: .download, title: "保存到相册", identifier: "share.poster.save") { [weak self] in
            self?.dismissAndRun { self?.onSaveToLibrary() }
        }
        let divider = UIView()
        divider.backgroundColor = Palette.borderSoft
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        let shareRow = makeActionRow(icon: .share, title: "分享图片", identifier: "share.poster.send") { [weak self] in
            self?.dismissAndRun { self?.onShareImage() }
        }

        let card = UIView()
        card.backgroundColor = Palette.cardSoft
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1 / UIScreen.main.scale
        card.layer.borderColor = Palette.borderSoft.cgColor
        card.clipsToBounds = true
        let cardStack = UIStackView(arrangedSubviews: [saveRow, divider, shareRow])
        cardStack.axis = .vertical
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cancelButton.setTitleColor(Palette.secondaryText, for: .normal)
        cancelButton.backgroundColor = Palette.cardSoft
        cancelButton.layer.cornerRadius = 10
        cancelButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cancelButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, card, cancelButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(stack)

        panelBottomConstraint = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 260)
        panelWidthConstraint = panelView.widthAnchor.constraint(equalToConstant: min(view.bounds.width, 520))

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panelWidthConstraint,
            panelBottomConstraint,

            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            stack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func makeActionRow(icon: ParityIcon, title: String, identifier: String, handler: @escaping () -> Void) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = title
        control.accessibilityIdentifier = identifier
        control.addAction(UIAction { _ in handler() }, for: .touchUpInside)

        let iconView = UIImageView(image: icon.image(size: 18))
        iconView.tintColor = Palette.accent
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Palette.text
        label.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [iconView, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(row)

        NSLayoutConstraint.activate([
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: control.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -10)
        ])
        return control
    }

    private func dismissAndRun(_ action: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        dismiss(animated: false) {
            action()
        }
    }

    @objc private func dismissTapped() {
        guard !isClosing else { return }
        isClosing = true
        dismiss(animated: false)
    }
}
