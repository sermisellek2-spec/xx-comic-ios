import XCTest

/// Record the actual failed screen in a portable format even when Xcode's
/// automatically generated diagnostic attachment is not a PNG.
class ParityUITestCase: XCTestCase {
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 || (testRun?.unexpectedExceptionCount ?? 0) > 0 {
            let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation,
                                           uniformTypeIdentifier: "public.png")
            attachment.name = "failure-screen"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        try super.tearDownWithError()
    }
}
