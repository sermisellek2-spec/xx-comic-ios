import UIKit

@MainActor
final class SourceOptionScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        canCancelContentTouches = true
        delaysContentTouches = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        canCancelContentTouches = true
        delaysContentTouches = false
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        // A drag that starts on a source/filter control must scroll the list
        // and cancel that button's tap, rather than select an accidental source or filter.
        view is UIControl || super.touchesShouldCancel(in: view)
    }
}
