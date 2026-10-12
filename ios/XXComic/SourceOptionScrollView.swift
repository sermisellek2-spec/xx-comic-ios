import UIKit

@MainActor
final class SourceOptionScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        // A drag that starts on a source/filter button must scroll the list
        // and cancel that button's tap, rather than select an accidental source.
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}
