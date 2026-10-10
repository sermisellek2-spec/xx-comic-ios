import Foundation

/// Pure seek tracking session aligned with Android 2.0.40's `ReaderSeekSession`.
/// A touch gesture previews a value; only its matching release commits it.
public final class ReaderSeekSession: @unchecked Sendable {
    private var tracking = false
    private var canceledTouch = false
    private var token: Int64 = 0
    private var preview = 0

    public init() {}

    public func start(token: Int64, value: Int) {
        self.token = token
        self.preview = value
        self.tracking = true
        self.canceledTouch = false
    }

    public var isTracking: Bool { tracking }

    public func change(token: Int64, value: Int, fromUser: Bool) -> Int? {
        guard fromUser else { return nil }
        guard !canceledTouch else { return nil }
        guard tracking else { return value } // Non-touch changes commit immediately
        if self.token != token {
            cancel()
            return nil
        }
        preview = value
        return nil
    }

    public func stop(token: Int64) -> Int? {
        guard tracking else {
            canceledTouch = false
            return nil
        }
        tracking = false
        return self.token == token ? preview : nil
    }

    public func cancel() {
        canceledTouch = canceledTouch || tracking
        tracking = false
    }

    public static func bubbleLeft(center: Float, bubbleWidth: Int, viewportWidth: Int, margin: Int) -> Float {
        let maxPos = max(Float(margin), Float(viewportWidth - margin - bubbleWidth))
        return max(Float(margin), min(maxPos, center - Float(bubbleWidth) / 2.0))
    }
}
