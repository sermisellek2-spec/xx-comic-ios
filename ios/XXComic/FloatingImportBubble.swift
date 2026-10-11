import UIKit

@MainActor
final class FloatingImportBubble: UIView {
    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private var initialCenter = CGPoint.zero
    private var isDragging = false
    private let bubbleSize: CGFloat = 54
    private let marginH: CGFloat = 16
    private let marginV: CGFloat = 20

    override init(frame: CGRect) {
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
            initialCenter = center
            isDragging = true
        case .changed:
            center = CGPoint(x: initialCenter.x + translation.x, y: initialCenter.y + translation.y)
        case .ended, .cancelled:
            isDragging = false
            snapToEdge()
        default:
            break
        }
    }

    func snapToEdge() {
        guard let superview else { return }
        let parentWidth = superview.bounds.width
        let parentHeight = superview.bounds.height
        let safeTop = superview.safeAreaInsets.top + marginV
        let safeBottom = parentHeight - superview.safeAreaInsets.bottom - marginV - bubbleSize

        let targetX = (center.x < parentWidth / 2) ? (marginH + bubbleSize / 2) : (parentWidth - marginH - bubbleSize / 2)
        let clampedY = min(max(center.y, safeTop + bubbleSize / 2), safeBottom + bubbleSize / 2)

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.center = CGPoint(x: targetX, y: clampedY)
        }
    }

    func positionInParent() {
        guard let superview else { return }
        let parentWidth = superview.bounds.width
        let parentHeight = superview.bounds.height
        let bottom = parentHeight - superview.safeAreaInsets.bottom - marginV - bubbleSize
        let x = parentWidth - marginH - bubbleSize
        frame = CGRect(x: x, y: bottom, width: bubbleSize, height: bubbleSize)
    }
}
