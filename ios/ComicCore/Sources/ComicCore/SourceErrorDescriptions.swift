import Foundation

extension HTTPTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "站源返回了无法识别的响应，请稍后重试。"
        case .unsupportedMethod: return "当前网络连接不支持该请求方式。"
        case .invalidStatusCode(let code): return "站源请求失败（HTTP \(code)），请稍后重试。"
        }
    }
}

extension GmhSourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "漫画链接无效，请重新打开作品。"
        case .invalidResponse: return "站源数据格式发生变化，暂时无法解析。"
        case .missingMangaID: return "无法识别作品编号，请重新搜索作品。"
        case .chapterNotFound: return "章节不存在或已更新，请刷新目录。"
        case .imageDecryptionFailed: return "章节图片解析失败，请重试或更换站源。"
        }
    }
}

extension BaoziSourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "漫画链接无效，请重新打开作品。"
        case .invalidResponse: return "站源数据格式发生变化，暂时无法解析。"
        }
    }
}
