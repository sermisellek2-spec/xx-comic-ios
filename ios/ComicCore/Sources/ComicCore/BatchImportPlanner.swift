import Foundation

public struct BatchImportCandidate: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case sourceOrderTooLong
        case invalidSourceOrder
    }

    public let sourceId: String
    public let remoteComicId: String
    public let seriesTitle: String
    public let fileName: String
    public let fileId: String
    public let sourceOrder: String?
    public let format: String
    public let fingerprint: String
    public let selectionIndex: Int
    fileprivate let decimalOrder: BatchDecimalOrder?

    public init(sourceId: String = "", remoteComicId: String = "", seriesTitle: String = "",
                fileName: String = "", fileId: String = "", sourceOrder: String? = nil,
                format: String = "", fingerprint: String = "", selectionIndex: Int = 0) throws {
        if let sourceOrder, sourceOrder.utf8.count > 1_048_576 { throw ValidationError.sourceOrderTooLong }
        let order = sourceOrder.map(SearchRules.trim).flatMap { $0.isEmpty ? nil : $0 }
        decimalOrder = try order.map(BatchDecimalOrder.init)
        self.sourceId = SearchRules.trim(sourceId)
        self.remoteComicId = SearchRules.trim(remoteComicId)
        self.seriesTitle = SearchRules.trim(seriesTitle)
        self.fileName = SearchRules.trim(fileName)
        self.fileId = SearchRules.trim(fileId)
        self.sourceOrder = order
        self.format = SearchRules.trim(format)
        self.fingerprint = SearchRules.trim(fingerprint)
        self.selectionIndex = max(0, selectionIndex)
    }
}

public struct BatchImportGroup: Equatable, Sendable {
    public let key: String
    public let title: String
    public let requiresConfirmation: Bool
    public let volumes: [BatchImportCandidate]
}

public enum BatchImportPlanner {
    private static let whitespace = #"[ \t\n\x0B\f\r]"#
    private static let separators = #"[ \t\n\x0B\f\r_\-()\[\]]"#
    private static let volumeWord = #"(?:[vV][oO][lL](?:[uU][mM][eE])?|[vV])\.?"#
    private static let extensionPattern = try! NSRegularExpression(pattern: #"\.[a-zA-Z0-9]{1,8}$"#)
    private static let volumePattern = try! NSRegularExpression(pattern:
        "(?:第\(whitespace)*([0-9]+)\(whitespace)*[卷册集话章]|\(volumeWord)\(whitespace)*([0-9]+)|(?:^|\(separators))([0-9]{1,4})(?=[^0-9]*$))")
    private static let suffixPattern = try! NSRegularExpression(pattern:
        "\(separators)*(?:第\(whitespace)*[0-9]+\(whitespace)*[卷册集话章]|\(volumeWord)\(whitespace)*[0-9]+|[0-9]{1,4})\(whitespace)*$")
    private static let trailingPattern = try! NSRegularExpression(pattern: #"[ \t\n\x0B\f\r_\-]+$"#)
    private static let spacesPattern = try! NSRegularExpression(pattern: "\(whitespace)+")

    public static func plan(_ candidates: [BatchImportCandidate]) -> [BatchImportGroup] {
        var groups: [BatchImportGroup] = []
        // Java String keys compare code units, not Swift's canonical equivalence.
        var indices: [Data: Int] = [:]
        var volumes: [[BatchImportCandidate]] = []
        for candidate in candidates {
            let title = candidate.seriesTitle.isEmpty ? normalizeTitle(candidate.fileName) : candidate.seriesTitle
            let confirmation = candidate.sourceId.isEmpty || candidate.remoteComicId.isEmpty
            let key = confirmation ? "local:\(title.lowercased())" : "remote:\(candidate.sourceId):\(candidate.remoteComicId)"
            let identity = Data(key.utf8)
            let index: Int
            if let existing = indices[identity] { index = existing }
            else {
                index = groups.count
                indices[identity] = index
                groups.append(BatchImportGroup(key: key, title: title, requiresConfirmation: confirmation, volumes: []))
                volumes.append([])
            }
            if candidate.fingerprint.isEmpty || !volumes[index].contains(where: { sameFingerprint($0.fingerprint, candidate.fingerprint) }) {
                volumes[index].append(candidate)
            }
        }
        return groups.enumerated().map { index, group in
            BatchImportGroup(key: group.key, title: group.title, requiresConfirmation: group.requiresConfirmation,
                             volumes: orderVolumes(volumes[index]))
        }
    }

    public static func orderVolumes(_ candidates: [BatchImportCandidate]) -> [BatchImportCandidate] {
        let entries = candidates.enumerated().map { (index: $0.offset, candidate: $0.element, volume: volumeNumber($0.element.fileName)) }
        return entries.sorted { a, b in
            if let left = a.candidate.decimalOrder, let right = b.candidate.decimalOrder {
                let order = left.compare(right)
                if order != 0 { return order < 0 }
            } else if (a.candidate.decimalOrder != nil) != (b.candidate.decimalOrder != nil) {
                return a.candidate.decimalOrder != nil
            }
            if a.volume >= 0 && b.volume >= 0 && a.volume != b.volume { return a.volume < b.volume }
            if (a.volume >= 0) != (b.volume >= 0) { return a.volume >= 0 }
            if NaturalPathOrder.less(a.candidate.fileName, b.candidate.fileName) { return true }
            if NaturalPathOrder.less(b.candidate.fileName, a.candidate.fileName) { return false }
            if a.candidate.selectionIndex != b.candidate.selectionIndex { return a.candidate.selectionIndex < b.candidate.selectionIndex }
            return a.index < b.index
        }.map(\.candidate)
    }

    public static func normalizeTitle(_ fileName: String) -> String {
        var value = replacing(extensionPattern, in: SearchRules.trim(fileName))
        value = SearchRules.trim(value.replacingOccurrences(of: "\u{3000}", with: " "))
        value = replacing(suffixPattern, in: value)
        value = replacing(trailingPattern, in: value)
        value = SearchRules.trim(replacing(spacesPattern, in: value, with: " "))
        return value.isEmpty ? "未命名漫画" : value
    }

    public static func volumeNumber(_ fileName: String) -> Int {
        let text = fileName as NSString
        var result = -1
        for match in volumePattern.matches(in: fileName, range: NSRange(location: 0, length: text.length)) {
            for group in 1...3 where match.range(at: group).location != NSNotFound {
                if let number = Int32(text.substring(with: match.range(at: group))) { result = Int(number) }
            }
        }
        return result
    }

    private static func replacing(_ pattern: NSRegularExpression, in text: String, with replacement: String = "") -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    private static func sameFingerprint(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.utf16.count == rhs.utf16.count else { return false }
        // Java equalsIgnoreCase uses simple, one-code-point casing. Full string folding
        // would incorrectly merge sharp-s/ss and canonically equivalent text.
        func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
            let upper = String(scalar).uppercased().unicodeScalars
            let simpleUpper = upper.count == 1 ? upper.first! : scalar
            if simpleUpper.value == 0x0130 { return "i" }
            let lower = String(simpleUpper).lowercased().unicodeScalars
            return lower.count == 1 ? lower.first! : simpleUpper
        }
        return lhs.unicodeScalars.map(folded).elementsEqual(rhs.unicodeScalars.map(folded))
    }
}

/// Only the representation and comparison needed for Android BigDecimal ordering.
/// No arithmetic and no zero expansion for exponents approaching Int32 limits.
fileprivate struct BatchDecimalOrder: Equatable, Sendable {
    let sign: Int
    let digits: [UInt8]
    let magnitude: Int64

    init(_ text: String) throws {
        let bytes = Array(text.utf8)
        var index = 0
        var negative = false
        if bytes.first == 43 || bytes.first == 45 { negative = bytes[0] == 45; index += 1 }
        var significant: [UInt8] = []
        var fraction: Int64 = 0
        var decimalPoint = false
        var hasDigit = false
        while index < bytes.count {
            let byte = bytes[index]
            if (48...57).contains(byte) {
                hasDigit = true
                if byte != 48 || !significant.isEmpty { significant.append(byte) }
                if decimalPoint { fraction += 1 }
            } else if byte == 46 && !decimalPoint { decimalPoint = true }
            else { break }
            index += 1
        }
        guard hasDigit else { throw BatchImportCandidate.ValidationError.invalidSourceOrder }
        var exponent: Int64 = 0
        if index < bytes.count && (bytes[index] == 101 || bytes[index] == 69) {
            index += 1
            var negativeExponent = false
            if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) {
                negativeExponent = bytes[index] == 45
                index += 1
            }
            let start = index
            while index < bytes.count && (48...57).contains(bytes[index]) {
                exponent = exponent * 10 + Int64(bytes[index] - 48)
                guard exponent <= Int32.max else { throw BatchImportCandidate.ValidationError.invalidSourceOrder }
                index += 1
            }
            guard index > start else { throw BatchImportCandidate.ValidationError.invalidSourceOrder }
            if negativeExponent { exponent = -exponent }
        }
        let scale = fraction - exponent
        guard index == bytes.count, scale >= Int32.min, scale <= Int32.max else {
            throw BatchImportCandidate.ValidationError.invalidSourceOrder
        }
        digits = significant
        sign = significant.isEmpty ? 0 : (negative ? -1 : 1)
        magnitude = Int64(significant.count) - scale
    }

    func compare(_ other: Self) -> Int {
        if sign != other.sign { return sign < other.sign ? -1 : 1 }
        if sign == 0 { return 0 }
        if magnitude != other.magnitude { return (magnitude < other.magnitude ? -1 : 1) * sign }
        for index in 0..<max(digits.count, other.digits.count) {
            let left = index < digits.count ? digits[index] : 48
            let right = index < other.digits.count ? other.digits[index] : 48
            if left != right { return (left < right ? -1 : 1) * sign }
        }
        return 0
    }
}
