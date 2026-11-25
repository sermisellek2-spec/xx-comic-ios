import UIKit
import ComicCore

/// Dedicated 44pt touch rail aligned 1:1 with Android 2.0.56's `ChapterFastScroller`.
/// Allows fast scrubbing without fighting sheet gestures or row clicks.
@MainActor
final class ChapterFastScroller: UIView, UIGestureRecognizerDelegate {
    private weak var tableView: UITableView?
    private let accentColor: UIColor
    private let trackColor: UIColor
    private var isDragging = false
    private var lastScrollable: Bool?
    private var panTargetY: CGFloat = 0

    var onScrollableChanged: ((Bool) -> Void)?

    var isScrollable: Bool {
        guard let tableView,
              tableView.numberOfSections > 0,
              tableView.numberOfRows(inSection: 0) > 0,
              tableView.bounds.height > 0 else {
            return false
        }
        return tableView.contentSize.height > tableView.bounds.height + 1.0
    }

    init(tableView: UITableView, accentColor: UIColor = Palette.accent, trackColor: UIColor = Palette.borderSoft) {
        self.tableView = tableView
        self.accentColor = accentColor
        self.trackColor = trackColor
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "快速定位章节，上下拖动滚动"

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func refreshScrollableState() {
        let scrollable = isScrollable
        isHidden = !scrollable
        isUserInteractionEnabled = scrollable
        if lastScrollable != scrollable {
            lastScrollable = scrollable
            onScrollableChanged?(scrollable)
        }
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshScrollableState()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard isScrollable, let tableView else { return }

        let halfWidth: CGFloat = 2.0
        let inset: CGFloat = 12.0
        let thumbHeight: CGFloat = 32.0
        let bottom = max(inset, bounds.height - inset)
        let centerX = bounds.width / 2.0

        let maxScroll = tableView.contentSize.height - tableView.bounds.height
        let fraction = max(0.0, min(1.0, tableView.contentOffset.y / max(1.0, maxScroll)))
        let thumbY = inset + fraction * max(0.0, bottom - inset - thumbHeight)

        // Draw track
        let trackPath = UIBezierPath(roundedRect: CGRect(x: centerX - halfWidth, y: inset, width: halfWidth * 2, height: bottom - inset), cornerRadius: halfWidth)
        trackColor.setFill()
        trackPath.fill()

        // Draw thumb
        let thumbPath = UIBezierPath(roundedRect: CGRect(x: centerX - halfWidth, y: thumbY, width: halfWidth * 2, height: thumbHeight), cornerRadius: halfWidth)
        accentColor.setFill()
        thumbPath.fill()
    }

    private func scroll(to y: CGFloat) {
        guard isScrollable, let tableView, tableView.numberOfRows(inSection: 0) > 0 else { return }
        let inset: CGFloat = 12.0
        let fraction = max(0.0, min(1.0, (y - inset) / max(1.0, bounds.height - 2 * inset)))
        let maxOffset = max(0.0, tableView.contentSize.height - tableView.bounds.height)
        if maxOffset > 0 {
            let targetOffset = CGPoint(x: tableView.contentOffset.x, y: fraction * maxOffset)
            tableView.setContentOffset(targetOffset, animated: false)
        } else {
            let totalRows = tableView.numberOfRows(inSection: 0)
            let targetRow = Int(round(fraction * CGFloat(totalRows - 1)))
            let indexPath = IndexPath(row: min(max(0, targetRow), totalRows - 1), section: 0)
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
        setNeedsDisplay()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isScrollable else {
            isDragging = false
            return
        }
        let inset: CGFloat = 12.0
        let minY = inset
        let maxY = max(inset, bounds.height - inset)
        switch recognizer.state {
        case .began:
            isDragging = true
            let touchY = recognizer.location(in: self).y
            panTargetY = min(maxY, max(minY, touchY))
            recognizer.setTranslation(.zero, in: self)
            scroll(to: panTargetY)
        case .changed:
            let deltaY = recognizer.translation(in: self).y
            recognizer.setTranslation(.zero, in: self)
            panTargetY = min(maxY, max(minY, panTargetY + deltaY))
            scroll(to: panTargetY)
        case .ended, .cancelled, .failed:
            isDragging = false
            setNeedsDisplay()
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        isScrollable
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isScrollable, let touch = touches.first else { return }
        isDragging = true
        panTargetY = touch.location(in: self).y
        scroll(to: panTargetY)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging, isScrollable, let touch = touches.first else { return }
        panTargetY = touch.location(in: self).y
        scroll(to: panTargetY)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDragging = false
        setNeedsDisplay()
    }
}
