/// Direction detection uses finger coordinates so header layout changes cannot
/// masquerade as a second drag. Matches the frozen Android threshold/anchor rule.
public struct DiscoveryHeaderGesture: Sendable {
    private var tracking = false
    private var startX = 0.0
    private var anchorY = 0.0
    public init() {}
    public mutating func begin(x: Double, y: Double) { tracking = true; startX = x; anchorY = y }
    public mutating func move(x: Double, y: Double, threshold: Double = 12) -> Int {
        guard tracking else { return 0 }
        let delta = y - anchorY
        guard abs(delta) >= threshold, abs(delta) > abs(x - startX) else { return 0 }
        anchorY = y
        return delta < 0 ? -1 : 1
    }
    public mutating func end() { tracking = false }
}
