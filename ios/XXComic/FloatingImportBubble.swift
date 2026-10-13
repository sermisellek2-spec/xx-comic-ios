import UIKit

@MainActor
final class FloatingImportBubble: UIView {
    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let defaults: UserDefaults
    private var initialOrigin = CGPoint.zero
    private var isDragging = false
    private let bubbleSize: CGFloat = 54
    private let marginH: CGFloat = 16
    private let marginTop: CGFloat = 16
    private let marginBottom: CGFloat = 20
    private let leftKey = "floating_bubble_snap_left"
    private let fractionKey = "floating_bubble_y_fraction"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init(frame: CGRect(x: 0, y: 0, width: bubbleSize, height: bubbleSize))
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setupView() {
        isAccessibilityElement = true; accessibilityTraits = .button
        accessibilityLabel = "导入"; accessibilityIdentifier = "bookshelf.import"
        backgroundColor = Palette.accent
        layer.cornerRadius = bubbleSize / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 5

        let plusConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.image = UIImage(systemName: "plus", withConfiguration: plusConfig)
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: pan)
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTap?()
    }
    override func accessibilityActivate() -> Bool { onTap?(); return true }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .began:
            layer.removeAllAnimations()
            initialOrigin = frame.origin
            isDragging = true
        case .changed:
            guard let range = allowedOrigins else { return }
            frame.origin = CGPoint(x: min(max(initialOrigin.x + translation.x, range.minX), range.maxX),
                                   y: min(max(initialOrigin.y + translation.y, range.minY), range.maxY))
        case .ended, .cancelled:
            isDragging = false
            snapToEdge()
        default:
            break
        }
    }

    func snapToEdge() {
        guard let superview, let range = allowedOrigins else { return }
        let left = center.x < superview.bounds.midX
        let y = min(max(frame.minY, range.minY), range.maxY)
        let fraction = range.height > 0 ? (y - range.minY) / range.height : 1
        defaults.set(left, forKey: leftKey)
        defaults.set(Double(fraction), forKey: fractionKey)
        let target = CGPoint(x: left ? range.minX : range.maxX, y: y)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.frame.origin = target
        }
    }

    func positionInParent() {
        guard !isDragging, let range = allowedOrigins else { return }
        let stored = (defaults.object(forKey: fractionKey) as? NSNumber)?.doubleValue ?? 0.88
        let fraction = stored.isFinite ? min(max(CGFloat(stored), 0), 1) : 0.88
        let left = defaults.bool(forKey: leftKey)
        frame = CGRect(x: left ? range.minX : range.maxX, y: range.minY + fraction * range.height,
                       width: bubbleSize, height: bubbleSize)
    }

    private var allowedOrigins: CGRect? {
        guard let superview, superview.bounds.width > 0, superview.bounds.height > 0 else { return nil }
        let safe = superview.bounds.inset(by: superview.safeAreaInsets)
        let minimum = CGPoint(x: safe.minX + marginH, y: safe.minY + marginTop)
        return CGRect(x: minimum.x, y: minimum.y,
                      width: max(0, safe.maxX - marginH - bubbleSize - minimum.x),
                      height: max(0, safe.maxY - marginBottom - bubbleSize - minimum.y))
    }
}
