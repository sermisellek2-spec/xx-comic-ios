import UIKit
import ComicCore

/// Floating 44pt circular "back to top" pill matching Android's `BackToTopPolicy` and `SmoothScrollToTopHelper`.
@MainActor
final class BackToTopButton: UIControl {
    static let buttonSize: CGFloat = 44

    var onTap: (() -> Void)?
    private let iconView = UIImageView()
    private(set) var isShowing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Palette.card
        layer.cornerRadius = Self.buttonSize / 2
        layer.borderWidth = 1
        layer.borderColor = Palette.border.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "回到顶部"
        accessibilityIdentifier = "common.backToTop"

        iconView.image = ParityIcon.arrowUpTop.image(size: 20)
        iconView.tintColor = Palette.accent
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.buttonSize),
            heightAnchor.constraint(equalToConstant: Self.buttonSize),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        alpha = 0
        isHidden = true
        transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.82, y: 0.82)
    }

    @objc private func handleTap() {
        onTap?()
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? Palette.accentSoft : Palette.card
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = Palette.border.resolvedColor(with: traitCollection).cgColor
    }

    func setVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != isShowing else { return }
        isShowing = visible
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let shouldAnimate = animated && !reduceMotion && window != nil
        if visible {
            isHidden = false
            if !shouldAnimate {
                alpha = 1
                transform = .identity
                return
            }
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.2,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.alpha = 1
                self.transform = .identity
            }
        } else {
            let hiddenTransform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.82, y: 0.82)
            if !shouldAnimate {
                alpha = 0
                transform = hiddenTransform
                isHidden = true
                return
            }
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.alpha = 0
                self.transform = hiddenTransform
            } completion: { _ in
                if !self.isShowing {
                    self.isHidden = true
                }
            }
        }
    }

    func updateScrollState(
        scrollView: UIScrollView,
        dy: CGFloat,
        firstVisibleIndex: Int = 0,
        spanCount: Int = 1,
        isMixedFullSpanList: Bool = false,
        scrollState: Int? = nil
    ) {
        let topOffset = -scrollView.adjustedContentInset.top
        let scrollOffsetPx = Int(max(0, scrollView.contentOffset.y - topOffset).rounded())
        let viewportHeightPx = Int(max(0, scrollView.bounds.height).rounded())
        let eligible = BackToTopPolicy.isEligible(
            firstVisible: firstVisibleIndex,
            scrollOffsetPx: scrollOffsetPx,
            viewportHeightPx: viewportHeightPx,
            spanCount: spanCount,
            isMixedFullSpanList: isMixedFullSpanList
        )
        let resolvedState: Int
        if let scrollState {
            resolvedState = scrollState
        } else if scrollView.isDragging {
            resolvedState = BackToTopPolicy.scrollStateDragging
        } else if scrollView.isDecelerating {
            resolvedState = BackToTopPolicy.scrollStateSettling
        } else {
            resolvedState = BackToTopPolicy.scrollStateIdle
        }
        let nextVisible = BackToTopPolicy.nextVisibility(
            currentVisible: isShowing,
            eligible: eligible,
            dy: Int(dy.rounded()),
            scrollState: resolvedState
        )
        setVisible(nextVisible, animated: true)
    }

    static func smoothScrollToTop(_ scrollView: UIScrollView) {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()

        let topOffset = CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
        let distance = max(0, scrollView.contentOffset.y - topOffset.y)
        guard distance > 0 else { return }

        if UIAccessibility.isReduceMotionEnabled {
            scrollView.setContentOffset(topOffset, animated: false)
            return
        }

        let viewportH = max(1, scrollView.bounds.height)
        let jumpThreshold = viewportH * 5
        if distance > jumpThreshold {
            let jumpY = topOffset.y + viewportH * 2.5
            scrollView.setContentOffset(CGPoint(x: topOffset.x, y: jumpY), animated: false)
        }
        let durationMs = BackToTopPolicy.computeSmoothDurationMs(
            distancePx: Int(min(distance, jumpThreshold).rounded()),
            density: Float(scrollView.traitCollection.displayScale > 0 ? scrollView.traitCollection.displayScale : 1)
        )
        let duration = TimeInterval(durationMs) / 1000.0
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            scrollView.contentOffset = topOffset
        }
    }
}
