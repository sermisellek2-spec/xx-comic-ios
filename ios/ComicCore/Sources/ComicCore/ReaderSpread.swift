import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - SHA-256 Utility

enum CoreSHA256 {
    static func digestHex(_ string: String) -> String {
        let data = Data(string.utf8)
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
        #else
        return fallbackHex(data)
        #endif
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private static func fallbackHex(_ data: Data) -> String {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        var message = Array(data)
        let bitLength = UInt64(data.count) * 8
        message.append(0x80)
        while (message.count * 8) % 512 != 448 {
            message.append(0x00)
        }
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLength >> (i * 8)) & 0xff))
        }
        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = (UInt32(message[offset]) << 24) |
                       (UInt32(message[offset + 1]) << 16) |
                       (UInt32(message[offset + 2]) << 8) |
                       UInt32(message[offset + 3])
            }
            for i in 16..<64 {
                let s0 = (w[i - 15] >> 7 | w[i - 15] << 25) ^
                         (w[i - 15] >> 18 | w[i - 15] << 14) ^
                         (w[i - 15] >> 3)
                let s1 = (w[i - 2] >> 17 | w[i - 2] << 15) ^
                         (w[i - 2] >> 19 | w[i - 2] << 13) ^
                         (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hVal = h[7]
            for i in 0..<64 {
                let s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hVal &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hVal = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ hVal
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}

// MARK: - SpreadDetectorPixels Protocol

public protocol SpreadDetectorPixels {
    var width: Int { get }
    var height: Int { get }
    func argb(x: Int, y: Int) -> UInt32
}

// MARK: - SpreadDetector

/// Conservative, local seam analysis. Scores are evidence measures, not probabilities.
public enum SpreadDetector {
    public static let VERSION: Int = 1
    private static let HEIGHT: Int = 384
    private static let EDGE: Int = 16
    private static let TRIMS: [Int] = [0, 1, 2, 4, 8]

    public typealias Pixels = SpreadDetectorPixels

    public final class Sample {
        public let width: Int
        public let height: Int
        fileprivate let left: [[Float]]
        fileprivate let right: [[Float]]
        fileprivate let content: [Float]

        fileprivate init(width: Int, height: Int, left: [[Float]], right: [[Float]], content: [Float]) {
            self.width = width
            self.height = height
            self.left = left
            self.right = right
            self.content = content
        }

        public static func read(_ pixels: SpreadDetectorPixels) -> Sample? {
            let w = pixels.width
            let h = pixels.height
            guard w >= 32, h >= 32 else { return nil }

            var left = Array(repeating: Array(repeating: Float(0), count: HEIGHT), count: EDGE)
            var right = Array(repeating: Array(repeating: Float(0), count: HEIGHT), count: EDGE)

            for col in 0..<EDGE {
                let lx = Double(col) * Double(h) / Double(HEIGHT)
                let rx = Double(w - 1) - Double(col) * Double(h) / Double(HEIGHT)
                for y in 0..<HEIGHT {
                    let sy = Double(y) * Double(h - 1) / Double(HEIGHT - 1)
                    left[col][y] = grey(pixels: pixels, x: lx, y: sy)
                    right[col][y] = grey(pixels: pixels, x: rx, y: sy)
                }
            }

            var content = Array(repeating: Float(0), count: 256)
            for y in 0..<16 {
                for x in 0..<16 {
                    let cx = (Double(x) + 0.5) * Double(w) / 16.0 - 0.5
                    let cy = (Double(y) + 0.5) * Double(h) / 16.0 - 0.5
                    content[y * 16 + x] = grey(pixels: pixels, x: cx, y: cy)
                }
            }

            return Sample(width: w, height: h, left: left, right: right, content: content)
        }

        public var aspect: Double {
            height <= 0 ? 0 : Double(width) / Double(height)
        }
    }

    public struct Evidence: Equatable, Sendable {
        public let score: Double
        public let correlation: Double
        public let difference: Double
        public let informativeRegions: Int
        public let matchingRegions: Int

        public init(score: Double, correlation: Double, difference: Double,
                    informativeRegions: Int, matchingRegions: Int) {
            self.score = score
            self.correlation = correlation
            self.difference = difference
            self.informativeRegions = informativeRegions
            self.matchingRegions = matchingRegions
        }

        public var isSufficient: Bool {
            informativeRegions >= 4 && matchingRegions >= 4 && correlation >= 0.60
                && difference <= 60.0 && score >= 0.60
        }

        public func sufficient() -> Bool {
            isSufficient
        }
    }

    public struct Result: Equatable, Sendable {
        public let merge: Bool
        public let firstOnLeft: Bool
        public let forward: Evidence
        public let reverse: Evidence

        public init(merge: Bool, firstOnLeft: Bool, forward: Evidence, reverse: Evidence) {
            self.merge = merge
            self.firstOnLeft = firstOnLeft
            self.forward = forward
            self.reverse = reverse
        }
    }

    private static let EMPTY = Evidence(score: 0, correlation: 0, difference: 255,
                                        informativeRegions: 0, matchingRegions: 0)

    public static func detect(_ first: Sample?, _ second: Sample?) -> Result {
        guard let first, let second,
              portrait(first), portrait(second),
              abs(first.aspect - second.aspect) <= 0.18,
              !duplicate(first, second) else {
            return Result(merge: false, firstOnLeft: true, forward: EMPTY, reverse: EMPTY)
        }

        let forward = compare(first.right, second.left)
        let reverse = compare(second.right, first.left)
        let direction = forward.score >= reverse.score
        let best = direction ? forward : reverse
        let other = direction ? reverse : forward
        let merge = best.sufficient() && (best.score - other.score >= 0.16)
        return Result(merge: merge, firstOnLeft: direction, forward: forward, reverse: reverse)
    }

    private static func portrait(_ sample: Sample) -> Bool {
        sample.aspect >= 0.35 && sample.aspect < 0.94
    }

    private static func duplicate(_ a: Sample, _ b: Sample) -> Bool {
        var diff: Double = 0
        for i in 0..<a.content.count {
            diff += abs(Double(a.content[i] - b.content[i]))
        }
        return diff / Double(a.content.count) < 7.0
    }

    private static func compare(_ a: [[Float]], _ b: [[Float]]) -> Evidence {
        var best = EMPTY
        let start = 46
        let end = 338

        for count in [1, 3] {
            for trimA in TRIMS {
                for trimB in TRIMS {
                    let left = profile(edge: a, trim: trimA, count: count)
                    let right = profile(edge: b, trim: trimB, count: count)
                    for shift in -3...3 {
                        let from = max(start, start - shift)
                        let to = min(end, end - shift)
                        let global = stats(a: left, b: right, from: from, to: to, shift: shift)
                        if global.stdA < 20 || global.stdB < 20 { continue }

                        var informative = 0
                        var matches = 0
                        var regionMask = 0

                        for region in 0..<8 {
                            let lo = from + (to - from) * region / 8
                            let hi = from + (to - from) * (region + 1) / 8
                            let local = stats(a: left, b: right, from: lo, to: hi, shift: shift)
                            if local.stdA < 20 || local.stdB < 20 { continue }
                            informative += 1
                            if local.correlation > 0.60 && local.difference < 65 {
                                matches += 1
                                regionMask |= 1 << (region / 2)
                            }
                        }

                        if regionMask.nonzeroBitCount < 3 {
                            matches = 0
                        }

                        let score = global.correlation * 0.55 + max(0, 1.0 - global.difference / 160.0) * 0.25 + Double(matches) / 8.0 * 0.20
                        let evidence = Evidence(score: score, correlation: global.correlation,
                                                difference: global.difference,
                                                informativeRegions: informative,
                                                matchingRegions: matches)
                        if (evidence.sufficient() && !best.sufficient())
                            || (evidence.sufficient() == best.sufficient() && evidence.score > best.score) {
                            best = evidence
                        }
                    }
                }
            }
        }
        return best
    }

    private static func profile(edge: [[Float]], trim: Int, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: HEIGHT)
        let divisor = Float(count)
        for y in 0..<HEIGHT {
            var sum: Float = 0
            for x in trim..<(trim + count) {
                sum += edge[x][y]
            }
            result[y] = sum / divisor
        }
        return result
    }

    private struct Stats {
        var stdA: Double = 0
        var stdB: Double = 0
        var correlation: Double = 0
        var difference: Double = 0
    }

    private static func stats(a: [Float], b: [Float], from: Int, to: Int, shift: Int) -> Stats {
        var sumA: Double = 0
        var sumB: Double = 0
        var squareA: Double = 0
        var squareB: Double = 0
        var product: Double = 0
        var diff: Double = 0

        let n = max(1, to - from)
        let doubleN = Double(n)

        for i in from..<to {
            let x = Double(a[i])
            let y = Double(b[i + shift])
            sumA += x
            sumB += y
            squareA += x * x
            squareB += y * y
            product += x * y
            diff += abs(x - y)
        }

        let varA = max(0, squareA / doubleN - (sumA * sumA) / (doubleN * doubleN))
        let varB = max(0, squareB / doubleN - (sumB * sumB) / (doubleN * doubleN))
        let stdA = sqrt(varA)
        let stdB = sqrt(varB)
        let difference = diff / doubleN
        let correlation: Double
        if stdA * stdB < 1.0 {
            correlation = 0
        } else {
            correlation = (product / doubleN - (sumA * sumB) / (doubleN * doubleN)) / (stdA * stdB)
        }

        return Stats(stdA: stdA, stdB: stdB, correlation: correlation, difference: difference)
    }

    private static func grey(pixels: SpreadDetectorPixels, x: Double, y: Double) -> Float {
        let w = pixels.width
        let h = pixels.height
        let x0 = max(0, min(w - 1, Int(floor(x))))
        let y0 = max(0, min(h - 1, Int(floor(y))))
        let x1 = min(w - 1, x0 + 1)
        let y1 = min(h - 1, y0 + 1)
        let dx = max(0, min(1.0, x - Double(x0)))
        let dy = max(0, min(1.0, y - Double(y0)))

        let top = luma(pixels.argb(x: x0, y: y0)) * (1.0 - dx) + luma(pixels.argb(x: x1, y: y0)) * dx
        let bottom = luma(pixels.argb(x: x0, y: y1)) * (1.0 - dx) + luma(pixels.argb(x: x1, y: y1)) * dx
        return Float(top * (1.0 - dy) + bottom * dy)
    }

    private static func luma(_ argb: UInt32) -> Double {
        let alpha = Double((argb >> 24) & 0xff) / 255.0
        let r = Double((argb >> 16) & 0xff)
        let g = Double((argb >> 8) & 0xff)
        let b = Double(argb & 0xff)
        return (0.299 * r + 0.587 * g + 0.114 * b) * alpha + 255.0 * (1.0 - alpha)
    }
}

// MARK: - SpreadPagePlan

/// Presentation-only grouping. Original page identities and indices never change.
public final class SpreadPagePlan: @unchecked Sendable {
    public static let KEY_PREFIX = "reader-spread://"
    public static let keyPrefix = KEY_PREFIX

    public struct Decision: Equatable, Sendable {
        public let firstOnLeft: Bool
        public let score: Double

        public init(firstOnLeft: Bool, score: Double) {
            self.firstOnLeft = firstOnLeft
            self.score = score
        }
    }

    public struct Unit: Equatable, Sendable {
        public let first: Int
        public let last: Int
        public let firstUrl: String?
        public let secondUrl: String?
        public let key: String
        public let firstOnLeft: Bool
        /// True when this virtual unit is one half of a source image containing two pages.
        public let doublePage: Bool
        public let doubleOriginalUrl: String?
        public let doubleLeftHalf: Bool

        public var isSpread: Bool { secondUrl != nil }

        public var isDoublePage: Bool { doublePage }

        public func contains(_ source: Int) -> Bool {
            source >= first && source <= last
        }

        public func pageLabel() -> String {
            if doublePage {
                return "\(first + 1)" + (doubleLeftHalf ? "左" : "右")
            }
            return isSpread ? "\(first + 1)–\(last + 1)" : "\(first + 1)"
        }

        public func sourceAt(x: Double, leftFraction: Double) -> Int {
            if !isSpread { return first }
            let left = x < leftFraction
            return left == firstOnLeft ? first : last
        }

        public func sourceX(x: Double, leftFraction: Double) -> Double {
            if doublePage {
                return (SpreadPagePlan.clamp(x) + (doubleLeftHalf ? 0 : 1)) / 2.0
            }
            if !isSpread { return SpreadPagePlan.clamp(x) }
            return x < leftFraction
                ? SpreadPagePlan.clamp(x / leftFraction)
                : SpreadPagePlan.clamp((x - leftFraction) / (1.0 - leftFraction))
        }

        public func unitX(source: Int, x: Double, leftFraction: Double) -> Double {
            if doublePage {
                return SpreadPagePlan.clamp(x * 2.0 - (doubleLeftHalf ? 0 : 1))
            }
            if !isSpread { return SpreadPagePlan.clamp(x) }
            let left = (source == first) == firstOnLeft
            return left
                ? SpreadPagePlan.clamp(x) * leftFraction
                : leftFraction + SpreadPagePlan.clamp(x) * (1.0 - leftFraction)
        }

        fileprivate init(first: Int, last: Int, firstUrl: String?, secondUrl: String?,
                         firstOnLeft: Bool, context: String) {
            self.first = first
            self.last = last
            self.firstUrl = firstUrl
            self.secondUrl = secondUrl
            self.firstOnLeft = firstOnLeft
            if let secondUrl {
                self.key = SpreadPagePlan.KEY_PREFIX + SpreadPagePlan.hash(context + "\n" + (firstUrl ?? "") + "\n" + secondUrl + "\n" + String(firstOnLeft))
            } else {
                self.key = firstUrl ?? ""
            }
            self.doublePage = false
            self.doubleOriginalUrl = nil
            self.doubleLeftHalf = false
        }

        fileprivate init(source: Int, originalUrl: String, leftHalf: Bool, context: String) {
            self.first = source
            self.last = source
            self.firstUrl = nil
            self.secondUrl = nil
            self.firstOnLeft = true
            self.doublePage = true
            self.doubleOriginalUrl = originalUrl
            self.doubleLeftHalf = leftHalf
            self.key = DoublePagePlan.KEY_PREFIX + DoublePagePlan.hash(context + "\n" + String(source) + "\n" + originalUrl + "\n" + String(leftHalf))
        }
    }

    public let originals: [String]
    public let units: [Unit]
    public let displayKeys: [String]
    public let revision: String
    private let sourceToDisplay: [Int]

    public init(chapterIdentity: String, originals: [String], enabled: Bool,
                manual: [Int: Int] = [:], automatic: [Int: Decision] = [:]) {
        self.originals = originals
        var identity = chapterIdentity
        for url in originals {
            identity.append("\n")
            identity.append(url)
        }
        self.revision = SpreadPagePlan.hash(identity)

        var items = [Unit]()
        var keys = [String]()
        var mapping = [Int](repeating: 0, count: originals.count)

        var source = 0
        while source < originals.count {
            let rule: Int? = enabled ? manual[source] : nil
            let decision: Decision? = enabled ? automatic[source] : nil
            let forced = rule != nil && rule != 0
            let paired = (source + 1 < originals.count) && (forced || (rule == nil && decision != nil
                && !SpreadPagePlan.manuallyReserved(index: source, rules: manual)
                && SpreadPagePlan.unambiguous(index: source, automatic: automatic)))
            let direction = forced ? (rule! > 0) : (decision == nil || decision!.firstOnLeft)

            let unit = Unit(first: source,
                            last: paired ? source + 1 : source,
                            firstUrl: originals[source],
                            secondUrl: paired ? originals[source + 1] : nil,
                            firstOnLeft: direction,
                            context: revision)
            mapping[source] = items.count
            if paired {
                mapping[source + 1] = items.count
            }
            items.append(unit)
            keys.append(unit.key)
            source += paired ? 2 : 1
        }

        self.units = items
        self.displayKeys = keys
        self.sourceToDisplay = mapping
    }

    /// Adapts the double-page virtual units to the reader's common presentation lifecycle.
    public static func fromDoublePagePlan(_ source: DoublePagePlan) -> SpreadPagePlan {
        SpreadPagePlan(doubleSource: source)
    }

    private init(doubleSource source: DoublePagePlan) {
        self.originals = source.originals
        self.revision = source.revision + ":double:" + (source.rightFirst ? "R" : "L")
        var mapping = [Int](repeating: 0, count: source.originals.count)
        var built = [Unit]()
        var keys = [String]()

        for sourceUnit in source.units {
            let display = built.count
            if sourceUnit.source >= 0 && sourceUnit.source < mapping.count
                && (display == 0 || source.units[display - 1].source != sourceUnit.source) {
                mapping[sourceUnit.source] = display
            }
            let unit: Unit
            if sourceUnit.split {
                unit = Unit(source: sourceUnit.source, originalUrl: sourceUnit.originalUrl,
                            leftHalf: sourceUnit.leftHalf, context: revision)
            } else {
                unit = Unit(first: sourceUnit.source, last: sourceUnit.source,
                            firstUrl: sourceUnit.originalUrl, secondUrl: nil,
                            firstOnLeft: true, context: revision)
            }
            built.append(unit)
            keys.append(unit.key)
        }

        self.units = built
        self.displayKeys = keys
        self.sourceToDisplay = mapping
    }

    private static func manuallyReserved(index: Int, rules: [Int: Int]) -> Bool {
        let previous = rules[index - 1]
        let next = rules[index + 1]
        return previous != nil || next != nil
    }

    private static func unambiguous(index: Int, automatic: [Int: Decision]) -> Bool {
        guard let current = automatic[index] else { return false }
        let before = automatic[index - 1]
        let after = automatic[index + 1]
        let beforePass = before == nil || (current.score - before!.score >= 0.12)
        let afterPass = after == nil || (current.score - after!.score >= 0.12)
        return beforePass && afterPass
    }

    public func displayForSource(_ index: Int) -> Int {
        guard !sourceToDisplay.isEmpty else { return 0 }
        return sourceToDisplay[max(0, min(index, sourceToDisplay.count - 1))]
    }

    /// Restore physical source content, independent of detection changes or display order.
    public func displayForPosition(_ position: ReaderPosition?, focusX: Double = 0.5) -> Int {
        guard let position, !units.isEmpty else { return 0 }
        let display = displayForSource(position.imageIndex)
        let first = units[display]
        if !first.isDoublePage { return display }
        if focusX == 0.5 {
            return position.atEnd && position.imageIndex >= originals.count - 1 ? units.count - 1 : display
        }
        let left = focusX < 0.5
        return first.doubleLeftHalf == left ? display : min(display + 1, units.count - 1)
    }

    public func unit(at display: Int) -> Unit? {
        guard !units.isEmpty else { return nil }
        return units[max(0, min(display, units.count - 1))]
    }

    public func unit(_ display: Int) -> Unit? {
        unit(at: display)
    }

    public static func finite(_ value: Double) -> Bool {
        !value.isNaN && !value.isInfinite
    }

    public static func clamp(_ value: Double) -> Double {
        finite(value) ? max(0, min(1.0, value)) : 0.5
    }

    public static func hash(_ value: String) -> String {
        CoreSHA256.digestHex(value)
    }
}

// MARK: - SpreadStateStore

public enum SpreadStateError: LocalizedError {
    case invalidRule(String)
    case corruptManualRecord(String)
    case occupiedByOtherSpread(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRule(let msg), .corruptManualRecord(let msg), .occupiedByOtherSpread(let msg):
            return msg
        }
    }
}

/// Feature-local preferences. Never changes the local library, originals, or legacy reading data.
public final class SpreadStateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func bookKey(_ book: String) -> String {
        "book." + SpreadPagePlan.hash(book) + "."
    }

    public func chapterKey(_ book: String, revision: String) -> String {
        bookKey(book) + revision + "."
    }

    public func enabled(_ book: String) -> Bool {
        defaults.bool(forKey: bookKey(book) + "enabled")
    }

    public func setEnabled(_ book: String, enabled: Bool) {
        defaults.set(enabled, forKey: bookKey(book) + "enabled")
    }

    public func manual(book: String, revision: String) throws -> [Int: Int] {
        lock.lock()
        defer { lock.unlock() }

        var result = [Int: Int]()
        let raw = defaults.string(forKey: chapterKey(book, revision: revision) + "manual") ?? "{}"
        guard let data = raw.data(using: .utf8) else {
            throw SpreadStateError.corruptManualRecord("跨页修正记录损坏，原始页面仍可阅读")
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SpreadStateError.corruptManualRecord("跨页修正记录损坏，原始页面仍可阅读")
            }
            for (key, val) in json {
                guard let index = Int(key), index >= 0,
                      let direction = (val as? NSNumber)?.intValue,
                      direction >= -1 && direction <= 1 else {
                    throw SpreadStateError.corruptManualRecord("跨页修正记录损坏，原始页面仍可阅读")
                }
                result[index] = direction
            }
        } catch {
            throw SpreadStateError.corruptManualRecord("跨页修正记录损坏，原始页面仍可阅读")
        }
        return result
    }

    public func manualRules(book: String, revision: String) -> [Int: Int] {
        (try? manual(book: book, revision: revision)) ?? [:]
    }

    public func setManual(book: String, revision: String, index: Int, direction: Int?) throws {
        lock.lock()
        defer { lock.unlock() }

        if index < 0 || (direction != nil && (direction! < -1 || direction! > 1)) {
            throw SpreadStateError.invalidRule("无效跨页修正")
        }

        var rules: [Int: Int]
        do {
            let raw = defaults.string(forKey: chapterKey(book, revision: revision) + "manual") ?? "{}"
            if let data = raw.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var loaded = [Int: Int]()
                for (key, val) in json {
                    if let k = Int(key), let v = (val as? NSNumber)?.intValue {
                        loaded[k] = v
                    }
                }
                rules = loaded
            } else {
                rules = [:]
            }
        } catch {
            rules = [:]
        }

        if let dir = direction, dir != 0 {
            if (rules[index - 1] != nil && rules[index - 1]! != 0) || (rules[index + 1] != nil && rules[index + 1]! != 0) {
                throw SpreadStateError.occupiedByOtherSpread("该页面已属于其他跨页，请先拆开原组")
            }
        }

        if let direction {
            rules[index] = direction
        } else {
            rules.removeValue(forKey: index)
        }

        var json = [String: Int]()
        for (k, v) in rules {
            json[String(k)] = v
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            throw SpreadStateError.invalidRule("跨页记录序列化失败")
        }
        defaults.set(text, forKey: chapterKey(book, revision: revision) + "manual")
    }

    public func clearManual(book: String) {
        lock.lock()
        defer { lock.unlock() }

        let prefix = bookKey(book)
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys {
            if key.hasPrefix(prefix) && key.hasSuffix(".manual") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    public func automatic(book: String, revision: String) -> [Int: SpreadPagePlan.Decision] {
        lock.lock()
        defer { lock.unlock() }

        var result = [Int: SpreadPagePlan.Decision]()
        let raw = defaults.string(forKey: chapterKey(book, revision: revision) + "auto.\(SpreadDetector.VERSION)") ?? "{}"
        guard let data = raw.data(using: .utf8) else { return result }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
                return result
            }
            for (key, val) in json {
                guard let index = Int(key), index >= 0,
                      let obj = val as? [String: Any],
                      let left = obj["left"] as? Bool,
                      let score = (obj["score"] as? NSNumber)?.doubleValue,
                      SpreadPagePlan.finite(score), score >= 0.60, score <= 1.01 else {
                    result.removeAll()
                    defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
                    return result
                }
                result[index] = SpreadPagePlan.Decision(firstOnLeft: left, score: score)
            }
        } catch {
            result.removeAll()
            defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
        }
        return result
    }

    public func saveAutomatic(book: String, revision: String,
                              decisions: [Int: SpreadPagePlan.Decision], complete: Bool) {
        lock.lock()
        defer { lock.unlock() }

        var dict = [String: [String: Any]]()
        for (k, decision) in decisions {
            dict[String(k)] = ["left": decision.firstOnLeft, "score": decision.score]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: chapterKey(book, revision: revision) + "auto.\(SpreadDetector.VERSION)")
        }
        defaults.set(complete, forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
    }

    public func complete(book: String, revision: String) -> Bool {
        defaults.bool(forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
    }

    public func retry(book: String, revision: String) {
        defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(SpreadDetector.VERSION)")
    }

    public func isEnabled(bookKey: String) -> Bool {
        enabled(bookKey)
    }

    public func setEnabled(bookKey: String, enabled: Bool) {
        setEnabled(bookKey, enabled: enabled)
    }

    public func load(bookKey: String, chapterKey: String) -> SpreadState {
        let rules = manualRules(book: bookKey, revision: chapterKey)
        var firsts = Set<Int>()
        for (idx, dir) in rules where dir == 1 {
            firsts.insert(idx)
        }
        let rtlKey = self.chapterKey(bookKey, revision: chapterKey) + "rtl"
        let rtl: Bool? = defaults.object(forKey: rtlKey) as? Bool
        return SpreadState(mergedFirsts: firsts, rightToLeft: rtl)
    }

    public func split(bookKey: String, chapterKey: String, first: Int) {
        try? setManual(book: bookKey, revision: chapterKey, index: first, direction: nil)
        try? setManual(book: bookKey, revision: chapterKey, index: first + 1, direction: nil)
    }

    public func merge(bookKey: String, chapterKey: String, first: Int) {
        try? setManual(book: bookKey, revision: chapterKey, index: first, direction: 1)
    }

    public func setRightToLeft(bookKey: String, chapterKey: String, rightToLeft: Bool) {
        let rtlKey = self.chapterKey(bookKey, revision: chapterKey) + "rtl"
        defaults.set(rightToLeft, forKey: rtlKey)
    }

    public func clearManual(bookKey: String, chapterKey: String) {
        defaults.removeObject(forKey: self.chapterKey(bookKey, revision: chapterKey) + "manual")
        defaults.removeObject(forKey: self.chapterKey(bookKey, revision: chapterKey) + "rtl")
    }
}

public struct SpreadState {
    public var mergedFirsts: Set<Int>
    public var rightToLeft: Bool?

    public init(mergedFirsts: Set<Int> = [], rightToLeft: Bool? = nil) {
        self.mergedFirsts = mergedFirsts
        self.rightToLeft = rightToLeft
    }

    public func isRightToLeft(defaultRightToLeft: Bool) -> Bool {
        rightToLeft ?? defaultRightToLeft
    }
}
