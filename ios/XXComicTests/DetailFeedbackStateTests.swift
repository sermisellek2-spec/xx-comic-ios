import XCTest
@testable import XXComic

final class DetailFeedbackStateTests: XCTestCase {
    func testLateDetailSuccessPreservesDownloadFailureAndRetry() {
        var state = DetailFeedbackState()
        state.setDetail("正在加载详情…")
        state.beginDownload()
        state.failDownload("暂无章节，请稍后重试 · 点击重试")
        state.setDetail(nil)
        XCTAssertEqual(state.message, "暂无章节，请稍后重试 · 点击重试")
        XCTAssertEqual(state.action, .retryDownload)
    }

    func testLateDetailFailureDoesNotChangeDownloadRetryAction() {
        var state = DetailFeedbackState()
        state.beginDownload()
        state.failDownload("下载目录失败 · 点击重试")
        state.setDetail("需要验证 · 去验证", action: .verifyDetail)
        XCTAssertEqual(state.message, "下载目录失败 · 点击重试")
        XCTAssertEqual(state.action, .retryDownload)
    }

    func testCancellingDownloadRestoresLatestDetailFailureAndAction() {
        var state = DetailFeedbackState()
        state.beginDownload()
        state.setDetail("需要验证 · 去验证", action: .verifyDetail)
        state.endDownload()
        XCTAssertEqual(state.message, "需要验证 · 去验证")
        XCTAssertEqual(state.action, .verifyDetail)
    }

    func testCancellingFailedDownloadRestoresDetailRetry() {
        var state = DetailFeedbackState()
        state.setDetail("详情失败 · 点击重试", action: .reloadDetail)
        XCTAssertEqual(state.message, "详情失败 · 点击重试")
        XCTAssertEqual(state.action, .reloadDetail)
        state.beginDownload()
        state.failDownload("下载目录失败 · 点击重试")
        state.endDownload()
        XCTAssertEqual(state.message, "详情失败 · 点击重试")
        XCTAssertEqual(state.action, .reloadDetail)
    }

    func testDownloadLoadingSuppressesDetailRetryUntilItEnds() {
        var state = DetailFeedbackState()
        state.setDetail("详情失败 · 点击重试", action: .reloadDetail)
        XCTAssertEqual(state.message, "详情失败 · 点击重试")
        XCTAssertEqual(state.action, .reloadDetail)
        state.beginDownload()
        XCTAssertNil(state.message)
        XCTAssertEqual(state.action, .none)
        state.setDetail(nil)
        state.endDownload()
        XCTAssertNil(state.message)
        XCTAssertEqual(state.action, .none)
    }

    func testLateDetailCompletionCannotEraseQueuedConfirmationOrMakeItRetry() {
        var state = DetailFeedbackState()
        state.beginDownload()
        state.endDownload()
        state.downloadQueued()
        state.setDetail(nil)
        XCTAssertEqual(state.message, "已加入下载队列")
        XCTAssertEqual(state.action, .none)
    }
}
