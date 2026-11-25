import Foundation

/// Pure chapter matching logic aligned 1:1 with Android 2.0.40's `findMatchingChapterIndex` and `normalizeChapterName`.
public enum ChapterMatching {
    /// Normalizes chapter title by stripping common punctuation, whitespace, and Chinese chapter markers.
    public static func normalizeChapterName(_ title: String?) -> String {
        guard let title = title, !title.isEmpty else { return "" }
        let pattern = "[\\s第话章节回卷【】\\[\\]()]"
        return title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).lowercased()
    }

    /// Finds matching chapter index across different sources by exact match, structured alignment via `FailoverChapterAligner`, or fallback index.
    public static func findMatchingChapterIndex(chapters: [Chapter], currentTitle: String?, defaultIndex: Int) -> Int {
        guard !chapters.isEmpty else { return 0 }
        if let currentTitle = currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !currentTitle.isEmpty {
            // 1. Exact case-insensitive match on trimmed title
            for (i, ch) in chapters.enumerated() {
                if ch.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(currentTitle) == .orderedSame {
                    return i
                }
            }
            // 2. Structured alignment without substring false positives
            let syntheticTarget = Chapter(chapterId: "", title: currentTitle, url: "", sectionSlot: 0, chapterSlot: Int.min)
            if let matched = FailoverChapterAligner.findMatchingChapter(target: syntheticTarget, candidates: chapters),
               let idx = chapters.firstIndex(of: matched) {
                return idx
            }
        }
        return max(0, min(defaultIndex, chapters.count - 1))
    }
}
