import Foundation

public struct ErrorLogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: String
    public let title: String
    public let message: String
    public let fullText: String

    public init(id: String = UUID().uuidString, timestamp: String, title: String, message: String, fullText: String) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.message = message
        self.fullText = fullText
    }
}

public final class ErrorLogStore: @unchecked Sendable {
    public static let shared = ErrorLogStore()
    public static let maxCharacters = 100_000
    public static let defaultKey = "error_logs"

    private let lock = NSLock()
    private let userDefaults: UserDefaults?
    private let fileURL: URL?
    private let key: String

    public init(userDefaults: UserDefaults? = .standard, fileURL: URL? = nil, key: String = defaultKey) {
        self.userDefaults = userDefaults
        self.fileURL = fileURL
        self.key = key
    }

    public func append(title: String, error: (any Error)? = nil, detail: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        var entry = "\(timestamp) · \(ErrorLogSanitizer.sanitize(title.trimmingCharacters(in: .whitespacesAndNewlines)))"
        if let error = error {
            let errorType = String(describing: type(of: error))
            let errorMsg = ErrorLogSanitizer.sanitize(error.localizedDescription)
            entry.append("\n\(errorType): \(errorMsg)")
        } else if let detail = detail, !detail.isEmpty {
            entry.append("\n\(ErrorLogSanitizer.sanitize(detail))")
        } else {
            entry.append("\n未知错误")
        }

        if let detail = detail, error != nil, !detail.isEmpty {
            entry.append("\n\(ErrorLogSanitizer.sanitize(detail))")
        }

        let current = loadTextLocked()
        var updated = current.isEmpty ? entry : "\(entry)\n\n\(current)"
        if updated.count > Self.maxCharacters {
            let endIndex = updated.index(updated.startIndex, offsetBy: Self.maxCharacters)
            updated = String(updated[..<endIndex])
        }

        saveTextLocked(updated)
    }

    public func allText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return loadTextLocked()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        let text = loadTextLocked().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 0 }
        return text.components(separatedBy: "\n\n").count
    }

    public func entries() -> [ErrorLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let text = loadTextLocked().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }

        let chunks = text.components(separatedBy: "\n\n")
        return chunks.compactMap { chunk in
            let lines = chunk.components(separatedBy: "\n")
            guard !lines.isEmpty else { return nil }

            let firstLine = lines[0]
            var timestamp = ""
            var title = firstLine
            if let separatorRange = firstLine.range(of: " · ") {
                timestamp = String(firstLine[..<separatorRange.lowerBound])
                title = String(firstLine[separatorRange.upperBound...])
            }

            let message = lines.count > 1 ? lines[1] : ""
            return ErrorLogEntry(timestamp: timestamp, title: title, message: message, fullText: chunk)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        saveTextLocked("")
    }

    private func loadTextLocked() -> String {
        if let fileURL = fileURL {
            return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
        return userDefaults?.string(forKey: key) ?? ""
    }

    private func saveTextLocked(_ text: String) {
        if let fileURL = fileURL {
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        userDefaults?.set(text, forKey: key)
    }
}
