import UIKit
import ComicCore

/// Dedicated 44pt touch rail aligned 1:1 with Android 2.0.40's `ChapterFastScroller`.
/// Allows fast scrubbing without fighting sheet gestures or row clicks.
@MainActor
final class ChapterFastScroller: UIView {
    private weak var tableView: UITableView?
    private let accentColor: UIColor
    private let trackColor: UIColor
    private var isDragging = false

    init(tableView: UITableView, accentColor: UIColor = Palette.accent, trackColor: UIColor = Palette.borderSoft) {
        self.tableView = tableView
        self.accentColor = accentColor
        self.trackColor = trackColor
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "快速定位章节，上下拖动滚动"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let tableView, tableView.contentSize.height > tableView.bounds.height else { return }

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
        guard let tableView, tableView.numberOfRows(inSection: 0) > 0 else { return }
        let inset: CGFloat = 12.0
        let fraction = max(0.0, min(1.0, (y - inset) / max(1.0, bounds.height - 2 * inset)))
        let totalRows = tableView.numberOfRows(inSection: 0)
        let targetRow = Int(round(fraction * CGFloat(totalRows - 1)))
        let indexPath = IndexPath(row: min(max(0, targetRow), totalRows - 1), section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        isDragging = true
        scroll(to: touch.location(in: self).y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging, let touch = touches.first else { return }
        scroll(to: touch.location(in: self).y)
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
