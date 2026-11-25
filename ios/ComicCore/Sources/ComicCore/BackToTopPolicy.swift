import Foundation

/// Pure Swift state machine and geometry/duration policy for the "Back to Top" floating action button.
public enum BackToTopPolicy {
    /// Mirrors `RecyclerView.SCROLL_STATE_IDLE`.
    public static let scrollStateIdle = 0
    /// Mirrors `RecyclerView.SCROLL_STATE_DRAGGING`.
    public static let scrollStateDragging = 1
    /// Mirrors `RecyclerView.SCROLL_STATE_SETTLING`.
    public static let scrollStateSettling = 2

    public static let fastDownHideDyPx = 24
    public static let upShowDyPx = -16

    public static let minSmoothDurationMs = 180
    public static let midSmoothDurationMs = 260
    public static let maxSmoothDurationMs = 360

    private static let nearDistanceDp: Float = 480
    private static let longDistanceSpanDp: Float = 1400

    /// Determines whether the list has scrolled past the first screen enough to allow showing the FAB.
    public static func isEligible(
        firstVisible: Int,
        scrollOffsetPx: Int,
        viewportHeightPx: Int,
        spanCount: Int,
        isMixedFullSpanList: Bool
    ) -> Bool {
        if firstVisible <= 0 && scrollOffsetPx <= 0 {
            return false
        }
        if viewportHeightPx > 0 && scrollOffsetPx >= Int(Float(viewportHeightPx) * 0.9) {
            return true
        }
        let safeSpan = max(1, spanCount)
        let posThreshold = isMixedFullSpanList ? 2 : max(6, safeSpan * 2)
        return firstVisible >= posThreshold
    }

    /// Computes the next visibility state based on eligibility, vertical scroll delta, and scroll state.
    public static func nextVisibility(
        currentVisible: Bool,
        eligible: Bool,
        dy: Int,
        scrollState: Int
    ) -> Bool {
        if !eligible {
            return false
        }
        if dy > fastDownHideDyPx {
            return false
        }
        if dy < upShowDyPx {
            return true
        }
        if scrollState == scrollStateIdle {
            return true
        }
        return currentVisible
    }

    /// Returns an intermediate jump-scroll position when the list is far from the top,
    /// or `-1` when direct smooth scrolling from the current position is preferred.
    public static func computeJumpPosition(
        firstVisible: Int,
        spanCount: Int,
        isMixedFullSpanList: Bool
    ) -> Int {
        let safeSpan = max(1, spanCount)
        let nearLimit = isMixedFullSpanList ? 12 : max(18, safeSpan * 6)
        if firstVisible > nearLimit {
            return isMixedFullSpanList ? 10 : max(12, safeSpan * 4)
        }
        return -1
    }

    /// Dynamically computes smooth deceleration duration in milliseconds from pixel distance and display density.
    /// Near distances are floored at `180ms`; medium-to-long distances clamp within `260...360ms`.
    public static func computeSmoothDurationMs(distancePx: Int, density: Float) -> Int {
        if distancePx <= 0 {
            return minSmoothDurationMs
        }
        let safeDensity: Float = density > 0 ? density : 1
        let distanceDp = Float(distancePx) / safeDensity
        if distanceDp <= nearDistanceDp {
            let delta = (distanceDp / nearDistanceDp) * Float(midSmoothDurationMs - minSmoothDurationMs)
            let duration = minSmoothDurationMs + Int(floor(Double(delta) + 0.5))
            return max(minSmoothDurationMs, min(midSmoothDurationMs, duration))
        }
        let extraRatio = min(Float(1), (distanceDp - nearDistanceDp) / longDistanceSpanDp)
        let delta = extraRatio * Float(maxSmoothDurationMs - midSmoothDurationMs)
        let duration = midSmoothDurationMs + Int(floor(Double(delta) + 0.5))
        return max(midSmoothDurationMs, min(maxSmoothDurationMs, duration))
    }
}
