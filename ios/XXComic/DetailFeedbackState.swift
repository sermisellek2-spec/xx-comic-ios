/// Keeps detail loading and download preparation feedback independent.
struct DetailFeedbackState {
    enum Action: Equatable { case none, reloadDetail, verifyDetail, retryDownload }
    private struct Feedback {
        let message: String?
        let action: Action
    }
    private var detail = Feedback(message: nil, action: .none)
    private var download: Feedback?

    var message: String? { (download ?? detail).message }
    var action: Action { (download ?? detail).action }

    mutating func setDetail(_ message: String?, action: Action = .none) {
        detail = Feedback(message: message, action: action)
    }
    mutating func beginDownload(message: String? = nil) {
        download = Feedback(message: message, action: .none)
    }
    mutating func failDownload(_ message: String) {
        download = Feedback(message: message, action: .retryDownload)
    }
    mutating func downloadQueued() {
        download = Feedback(message: "已加入下载队列", action: .none)
    }
    mutating func endDownload() { download = nil }
}
