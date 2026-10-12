#if DEBUG
import UIKit

/// Runtime geometry from the app's own scene, rather than the separate UI runner.
/// Enabled only in an explicitly isolated UI-test launch.
@MainActor
final class ParityGeometryWindow: UIWindow {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"), let scene = windowScene else { return }
        let screen = scene.screen
        let record: [String: Any] = [
            "bounds": [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height],
            "frame": [frame.origin.x, frame.origin.y, frame.width, frame.height],
            "sceneBounds": [scene.coordinateSpace.bounds.width, scene.coordinateSpace.bounds.height],
            "screenBounds": [screen.bounds.width, screen.bounds.height],
            "nativeScreenBounds": [screen.nativeBounds.width, screen.nativeBounds.height],
            "screenScale": screen.scale,
            "preferredContentSizeCategory": traitCollection.preferredContentSizeCategory.rawValue
        ]
        accessibilityIdentifier = "parity.window"
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            accessibilityValue = String(data: data, encoding: .utf8)
        } catch { accessibilityValue = "invalid-geometry" }
    }
}
#endif
