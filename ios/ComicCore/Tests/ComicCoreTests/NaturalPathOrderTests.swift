import XCTest
@testable import ComicCore

final class NaturalPathOrderTests: XCTestCase {
    func testNumericPageOrderAndLeadingZeroTies() {
        XCTAssertEqual(["10.jpg", "02.jpg", "2.jpg", "1.jpg"].sorted(by: NaturalPathOrder.less),
                       ["1.jpg", "2.jpg", "02.jpg", "10.jpg"])
    }
    func testFolderComponentsAreComparedBeforeLaterPageNames() {
        XCTAssertEqual(["卷10/1.jpg", "卷2/10.jpg", "卷2/2.jpg"].sorted(by: NaturalPathOrder.less),
                       ["卷2/2.jpg", "卷2/10.jpg", "卷10/1.jpg"])
        XCTAssertFalse(NaturalPathOrder.less("/卷2\\2.jpg/", "卷2/2.jpg"))
        XCTAssertFalse(NaturalPathOrder.less("卷2/2.jpg", "/卷2\\2.jpg/"))
    }
    func testLargeNumbersDoNotOverflowAndCaseTiePrecedesLaterNumbers() {
        XCTAssertTrue(NaturalPathOrder.less("999999999999999999999.jpg", "1000000000000000000000.jpg"))
        XCTAssertTrue(NaturalPathOrder.less("A10.jpg", "a2.jpg"))
        XCTAssertTrue(NaturalPathOrder.less("2.jpg", "a.jpg"))
        XCTAssertTrue(NaturalPathOrder.less("٢.jpg", "١٠.jpg"))
    }
}
