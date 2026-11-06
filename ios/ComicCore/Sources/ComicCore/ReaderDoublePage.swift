import Foundation

// MARK: - DoublePageDetector

/// Conservative detector for a landscape scan that contains two portrait comic pages.
/// The decision is made against the chapter's own aspect-ratio baseline so ordinary
/// landscape artwork is left untouched when the chapter is not consistently scanned.
public enum DoublePageDetector {
    public static let VERSION: Int = 3

    public struct Sample: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var aspect: Double {
            height <= 0 ? 0 : Double(width) / Double(height)
        }
    }

    public struct Decision: Equatable, Sendable {
        public let split: Bool
        public let score: Double
        public let aspect: Double

        public init(split: Bool, score: Double, aspect: Double) {
            self.split = split
            self.score = score
            self.aspect = aspect
        }
    }

    public static func measure(width: Int, height: Int) -> Sample? {
        if width < 256 || height < 128 {
            return nil
        }
        return Sample(width: width, height: height)
    }

    public static func median(_ samples: [Sample?]?) -> Double {
        guard let samples else { return 0 }
        var values = [Double]()
        for sample in samples {
            if let s = sample, s.aspect > 0 {
                values.append(s.aspect)
            }
        }
        guard !values.isEmpty else { return 0 }
        values.sort()
        let count = values.count
        let middle = count / 2
        return (count & 1) == 0 ? (values[middle - 1] + values[middle]) / 2.0 : values[middle]
    }

    public static func decide(sample: Sample?, chapterMedian: Double, index: Int = 0, count: Int = 0) -> Decision {
        // A landscape chapter is an opt-in indication of consistently scanned spreads.
        // Include narrower cover/back matter when its half still has portrait geometry.
        guard let sample, chapterMedian >= 1.05 else {
            return Decision(split: false, score: 0, aspect: 0)
        }
        let aspect = sample.aspect
        let minimum = max(1.05, chapterMedian * 0.72)
        let maximum = min(1.95, chapterMedian * 1.35)
        let wideEnough = aspect >= minimum && aspect <= maximum
        let distance = abs(aspect - chapterMedian)
        let consistency = max(0, 1.0 - distance / max(0.45, chapterMedian * 0.65))
        let widthEvidence = max(0, min(1.0, (aspect - 1.02) / 0.34))
        let score = max(0, min(1.0, 0.60 * consistency + 0.40 * widthEvidence))
        return Decision(split: wideEnough && score >= 0.40, score: score, aspect: aspect)
    }
}

// MARK: - DoublePagePlan

/// Presentation-only virtual pages for a scanned page containing two comic pages.
public final class DoublePagePlan: @unchecked Sendable {
    public static let KEY_PREFIX = "reader-double-page://"
    public static let keyPrefix = KEY_PREFIX

    public typealias Decision = DoublePageDetector.Decision

    public struct Unit: Equatable, Sendable {
        public let source: Int
        public let originalUrl: String
        public let key: String
        public let split: Bool
        public let leftHalf: Bool

        public init(source: Int, originalUrl: String, split: Bool, leftHalf: Bool,
                    rightFirst: Bool, context: String) {
            self.source = source
            self.originalUrl = originalUrl
            self.split = split
            self.leftHalf = leftHalf
            self.key = split
                ? DoublePagePlan.KEY_PREFIX + DoublePagePlan.hash(context + "\n" + String(source) + "\n" + originalUrl + "\n" + String(leftHalf) + "\n" + String(rightFirst))
                : originalUrl
        }

        public func pageLabel() -> String {
            split ? "\(source + 1)" + (leftHalf ? "左" : "右") : String(source + 1)
        }
    }

    public let originals: [String]
    public let units: [Unit]
    public let displayKeys: [String]
    public let revision: String
    public let enabled: Bool
    public let rightFirst: Bool
    private let sourceToDisplay: [Int]

    public init(chapterIdentity: String, originals: [String], enabled: Bool,
                rightFirst: Bool, manual: [Int: Int]? = nil,
                automatic: [Int: Decision]? = nil) {
        self.originals = originals
        self.enabled = enabled
        self.rightFirst = rightFirst

        var identity = chapterIdentity
        for url in originals {
            identity.append("\n")
            identity.append(url)
        }
        self.revision = DoublePagePlan.hash(identity)

        var mapping = [Int](repeating: 0, count: originals.count)
        var built = [Unit]()
        var keys = [String]()

        for source in 0..<originals.count {
            let manualMode = manual?[source]
            let decision = automatic?[source]
            let split = enabled && (manualMode != nil ? manualMode! == 1 : (decision != nil && decision!.split))
            mapping[source] = built.count

            if !split {
                let unit = Unit(source: source, originalUrl: originals[source],
                                split: false, leftHalf: false, rightFirst: rightFirst, context: revision)
                built.append(unit)
                keys.append(unit.key)
            } else {
                let firstLeft = !rightFirst
                let first = Unit(source: source, originalUrl: originals[source],
                                 split: true, leftHalf: firstLeft, rightFirst: rightFirst, context: revision)
                let second = Unit(source: source, originalUrl: originals[source],
                                  split: true, leftHalf: !firstLeft, rightFirst: rightFirst, context: revision)
                built.append(first)
                built.append(second)
                keys.append(first.key)
                keys.append(second.key)
            }
        }

        self.units = built
        self.displayKeys = keys
        self.sourceToDisplay = mapping
    }

    public func displayForSource(_ source: Int) -> Int {
        guard !sourceToDisplay.isEmpty else { return 0 }
        return sourceToDisplay[max(0, min(sourceToDisplay.count - 1, source))]
    }

    public func sourceForDisplay(_ display: Int) -> Int {
        guard !units.isEmpty else { return 0 }
        return units[max(0, min(units.count - 1, display))].source
    }

    public func unit(at display: Int) -> Unit? {
        guard !units.isEmpty else { return nil }
        return units[max(0, min(units.count - 1, display))]
    }

    public func unit(_ display: Int) -> Unit? {
        unit(at: display)
    }

    public func unitForKey(_ key: String?) -> Unit? {
        guard let key else { return nil }
        return units.first(where: { $0.key == key })
    }

    public static func hash(_ value: String) -> String {
        CoreSHA256.digestHex(value)
    }
}

// MARK: - DoublePageStateStore

public enum DoublePageStateError: LocalizedError {
    case invalidRule(String)
    case corruptRecord(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRule(let msg), .corruptRecord(let msg):
            return msg
        }
    }
}

/// Stores double-page presentation state separately from cross-page restoration.
public final class DoublePageStateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func bookKey(_ book: String) -> String {
        "book." + DoublePagePlan.hash(book) + "."
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

    /// Default reading direction is left source page first, then right source page.
    public func rightFirst(_ book: String) -> Bool {
        defaults.bool(forKey: bookKey(book) + "rightFirst")
    }

    public func setRightFirst(_ book: String, rightFirst: Bool) {
        defaults.set(rightFirst, forKey: bookKey(book) + "rightFirst")
    }

    public func manual(book: String, revision: String) throws -> [Int: Int] {
        lock.lock()
        defer { lock.unlock() }

        var result = [Int: Int]()
        let raw = defaults.string(forKey: chapterKey(book, revision: revision) + "manual") ?? "{}"
        guard let data = raw.data(using: .utf8) else {
            throw DoublePageStateError.corruptRecord("双页切分修正记录损坏，原始页面仍可阅读")
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DoublePageStateError.corruptRecord("双页切分修正记录损坏，原始页面仍可阅读")
            }
            for (key, val) in json {
                guard let index = Int(key), index >= 0,
                      let mode = (val as? NSNumber)?.intValue,
                      mode == -1 || mode == 1 else {
                    throw DoublePageStateError.corruptRecord("双页切分修正记录损坏，原始页面仍可阅读")
                }
                result[index] = mode
            }
        } catch {
            throw DoublePageStateError.corruptRecord("双页切分修正记录损坏，原始页面仍可阅读")
        }
        return result
    }

    public func manualRules(book: String, revision: String) -> [Int: Int] {
        (try? manual(book: book, revision: revision)) ?? [:]
    }

    public func setManual(book: String, revision: String, index: Int, mode: Int?) throws {
        lock.lock()
        defer { lock.unlock() }

        if index < 0 || (mode != nil && mode! != -1 && mode! != 1) {
            throw DoublePageStateError.invalidRule("无效双页切分修正")
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

        if let mode {
            rules[index] = mode
        } else {
            rules.removeValue(forKey: index)
        }

        var json = [String: Int]()
        for (k, v) in rules {
            json[String(k)] = v
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            throw DoublePageStateError.invalidRule("双页记录序列化失败")
        }
        defaults.set(text, forKey: chapterKey(book, revision: revision) + "manual")
    }

    public func automatic(book: String, revision: String) -> [Int: DoublePagePlan.Decision] {
        lock.lock()
        defer { lock.unlock() }

        var result = [Int: DoublePagePlan.Decision]()
        let raw = defaults.string(forKey: chapterKey(book, revision: revision) + "auto.\(DoublePageDetector.VERSION)") ?? "{}"
        guard let data = raw.data(using: .utf8) else { return result }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
                return result
            }
            for (key, val) in json {
                guard let index = Int(key), index >= 0,
                      let obj = val as? [String: Any],
                      let split = obj["split"] as? Bool,
                      let score = (obj["score"] as? NSNumber)?.doubleValue,
                      let aspect = (obj["aspect"] as? NSNumber)?.doubleValue,
                      SpreadPagePlan.finite(score), score >= 0, score <= 1.01,
                      SpreadPagePlan.finite(aspect), aspect > 0 else {
                    result.removeAll()
                    defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
                    return result
                }
                result[index] = DoublePagePlan.Decision(split: split, score: score, aspect: aspect)
            }
        } catch {
            result.removeAll()
            defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
        }
        return result
    }

    public func saveAutomatic(book: String, revision: String,
                              decisions: [Int: DoublePagePlan.Decision], complete: Bool) {
        lock.lock()
        defer { lock.unlock() }

        var dict = [String: [String: Any]]()
        for (k, decision) in decisions {
            dict[String(k)] = ["split": decision.split, "score": decision.score, "aspect": decision.aspect]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: chapterKey(book, revision: revision) + "auto.\(DoublePageDetector.VERSION)")
        }
        defaults.set(complete, forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
    }

    public func complete(book: String, revision: String) -> Bool {
        defaults.bool(forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
    }

    public func retry(book: String, revision: String) {
        defaults.removeObject(forKey: chapterKey(book, revision: revision) + "complete.\(DoublePageDetector.VERSION)")
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

    public func isEnabled(bookKey: String) -> Bool {
        enabled(bookKey)
    }

    public func setEnabled(bookKey: String, enabled: Bool) {
        setEnabled(bookKey, enabled: enabled)
    }

    public func load(bookKey: String, chapterKey: String) -> DoublePageState {
        let rules = manualRules(book: bookKey, revision: chapterKey)
        var splits = Set<Int>()
        for (idx, mode) in rules where mode == 1 {
            splits.insert(idx)
        }
        let rtl = rightFirst(bookKey)
        return DoublePageState(splitSources: splits, rightToLeft: rtl)
    }

    public func keepWhole(bookKey: String, chapterKey: String, sourceIndex: Int) {
        try? setManual(book: bookKey, revision: chapterKey, index: sourceIndex, mode: -1)
    }

    public func split(bookKey: String, chapterKey: String, sourceIndex: Int) {
        try? setManual(book: bookKey, revision: chapterKey, index: sourceIndex, mode: 1)
    }

    public func setRightToLeft(bookKey: String, chapterKey: String, rightToLeft: Bool) {
        setRightFirst(bookKey, rightFirst: rightToLeft)
    }

    public func clearManual(bookKey: String, chapterKey: String) {
        defaults.removeObject(forKey: self.chapterKey(bookKey, revision: chapterKey) + "manual")
    }
}

public struct DoublePageState {
    public var splitSources: Set<Int>
    public var rightToLeft: Bool?

    public init(splitSources: Set<Int> = [], rightToLeft: Bool? = nil) {
        self.splitSources = splitSources
        self.rightToLeft = rightToLeft
    }

    public func isRightToLeft(defaultRightToLeft: Bool) -> Bool {
        rightToLeft ?? defaultRightToLeft
    }
}
