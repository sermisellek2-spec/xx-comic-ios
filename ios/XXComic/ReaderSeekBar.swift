import UIKit
import ComicCore

/// Shared seekbar with touch preview bubble aligned 1:1 with Android 2.0.40's `ReaderSeekBar`.
@MainActor
final class ReaderSeekBar: UIView {
    private let slider = UISlider()
    private let bubble = UILabel()
    private let session = ReaderSeekSession()
    private var token: Int64 = 0
    private var committedValue: Int = 0
    private var totalPages: Int = 1

    var onCommit: ((Int) -> Void)?
    var onTracking: ((Bool) -> Void)?

    // A centered stack gives a plain UIView no height. The slider then draws
    // outside a zero-height parent, losing hit testing and accessibility.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = false

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.accessibilityIdentifier = "reader.seek"
        slider.accessibilityLabel = "本章阅读进度"
        slider.isAccessibilityElement = true
        updateAppearance()
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside])
        slider.addTarget(self, action: #selector(sliderTouchCancel), for: .touchCancel)
        addSubview(slider)

        bubble.font = .boldSystemFont(ofSize: 14)
        bubble.textColor = .white
        bubble.textAlignment = .center
        bubble.backgroundColor = UIColor(red: 12/255, green: 20/255, blue: 32/255, alpha: 0.94) // 0xF00C1420
        bubble.layer.cornerRadius = 8
        bubble.layer.masksToBounds = true
        bubble.isHidden = true
        bubble.isAccessibilityElement = false
        addSubview(bubble)

        // UIKit constrains a slider's alignment rectangle, which is inset
        // from its frame. Keep the entire touch frame inside this parent.
        let alignment = slider.alignmentRectInsets
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: alignment.left),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -alignment.right),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { updateAppearance() }
    }

    private func updateAppearance() {
        // Android's applyReaderThemeInPlace uses reader text ink for progress.
        // Custom images and slider tint properties are mutually exclusive.
        let ink = traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 235 / 255, green: 246 / 255, blue: 1, alpha: 1)
            : UIColor(red: 31 / 255, green: 35 / 255, blue: 40 / 255, alpha: 1)
        let remainder = UIColor(white: 0.6, alpha: 0.4)
        for state: UIControl.State in [.normal, .highlighted, .disabled] {
            let color = state == .disabled ? ink.withAlphaComponent(0.45) : ink
            let thumb = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { _ in
                color.setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 12, height: 12)).fill()
            }.withRenderingMode(.alwaysOriginal)
            func track(_ color: UIColor) -> UIImage {
                UIGraphicsImageRenderer(size: CGSize(width: 1, height: 2)).image { _ in
                    color.setFill()
                    UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 2)).fill()
                }.resizableImage(withCapInsets: .zero).withRenderingMode(.alwaysOriginal)
            }
            // The small visible thumb retains the 32-point slider and
            // 40-point parent used for touch and accessibility.
            slider.setThumbImage(thumb, for: state)
            slider.setMinimumTrackImage(track(color), for: state)
            slider.setMaximumTrackImage(track(remainder), for: state)
        }
    }

    func configure(currentPage: Int, total: Int, sessionToken: Int64 = 0) {
        self.totalPages = max(1, total)
        self.token = sessionToken
        self.committedValue = max(0, min(currentPage, totalPages - 1))
        slider.minimumValue = 0
        slider.maximumValue = Float(max(0, totalPages - 1))
        slider.value = Float(committedValue)
        slider.isEnabled = totalPages > 1
    }

    @objc private func sliderTouchDown() {
        let value = Int(round(slider.value))
        session.start(token: token, value: value)
        onTracking?(true)
        updateBubble(value: value)
        bubble.isHidden = false
    }

    @objc private func sliderValueChanged() {
        let value = Int(round(slider.value))
        let directCommit = session.change(token: token, value: value, fromUser: true)
        if let directCommit {
            committedValue = directCommit
            onCommit?(directCommit)
        } else if session.isTracking {
            updateBubble(value: value)
        }
    }

    @objc private func sliderTouchUp() {
        let target = session.stop(token: token)
        bubble.isHidden = true
        onTracking?(false)
        if let target {
            committedValue = target
            onCommit?(target)
        } else {
            slider.value = Float(committedValue)
        }
    }

    @objc private func sliderTouchCancel() {
        session.cancel()
        bubble.isHidden = true
        onTracking?(false)
        slider.value = Float(committedValue)
    }

    private func updateBubble(value: Int) {
        bubble.text = " \(value + 1) / \(totalPages) "
        bubble.sizeToFit()

        let bubbleW = bubble.bounds.width + 16
        let bubbleH = max(28, bubble.bounds.height + 8)

        // Calculate thumb center x coordinate
        let trackRect = slider.trackRect(forBounds: slider.bounds)
        let thumbRect = slider.thumbRect(forBounds: slider.bounds, trackRect: trackRect, value: slider.value)
        let thumbCenter = thumbRect.midX

        let viewportW = bounds.width > 0 ? bounds.width : 300
        let bubbleX = ReaderSeekSession.bubbleLeft(center: Float(thumbCenter), bubbleWidth: Int(bubbleW), viewportWidth: Int(viewportW), margin: 8)

        bubble.frame = CGRect(x: CGFloat(bubbleX), y: slider.frame.minY - bubbleH - 6, width: bubbleW, height: bubbleH)
    }
}
