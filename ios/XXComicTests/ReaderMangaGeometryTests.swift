import XCTest
import UIKit
@testable import XXComic

@MainActor
final class ReaderMangaGeometryTests: XCTestCase {
    private final class Pages: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var stripHeight: CGFloat = 500
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            guard let layout = collectionViewLayout as? ReaderPageLayout else { return .zero }
            return layout.scrollDirection == .horizontal ? collectionView.bounds.size : CGSize(width: collectionView.bounds.width, height: stripHeight)
        }
    }
    private func collection(_ source: Pages) -> UICollectionView {
        let layout = ReaderPageLayout()
        layout.scrollDirection = .horizontal
        layout.reversesPages = true
        layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0
        layout.itemSize = CGSize(width: 393, height: 600)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 393, height: 600), collectionViewLayout: layout)
        collection.semanticContentAttribute = .forceLeftToRight
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "page")
        collection.dataSource = source
        collection.reloadData(); collection.layoutIfNeeded()
        return collection
    }
    private func seek(_ index: Int, in collection: UICollectionView) -> Int? {
        XCTAssertTrue((collection.collectionViewLayout as? ReaderPageLayout)?.scrollToLogicalPage(index, animated: false) == true)
        collection.layoutIfNeeded()
        return collection.indexPathForItem(at: CGPoint(x: collection.bounds.midX, y: collection.bounds.midY))?.item
    }
    func testMangaFirstLogicalPageIsAtTheRightAndSeeksKeepLogicalOrder() {
        let source = Pages()
        let pages = collection(source)
        XCTAssertEqual(seek(0, in: pages), 0)
        let firstOffset = pages.contentOffset.x
        XCTAssertEqual(seek(1, in: pages), 1)
        XCTAssertEqual(seek(2, in: pages), 2)
        XCTAssertGreaterThan(firstOffset, pages.contentOffset.x, "日漫首逻辑页应位于末逻辑页右侧")
        (pages.collectionViewLayout as? ReaderPageLayout)?.reversesPages = false
        pages.collectionViewLayout.invalidateLayout(); pages.layoutIfNeeded()
        XCTAssertEqual(seek(0, in: pages), 0)
        let normalFirst = pages.contentOffset.x
        XCTAssertEqual(seek(2, in: pages), 2)
        XCTAssertLessThan(normalFirst, pages.contentOffset.x)
    }
    func testMangaResizeAndDirectionChangePreserveTheRequestedLogicalPage() throws {
        let source = Pages()
        let pages = collection(source)
        XCTAssertEqual(seek(1, in: pages), 1)
        pages.frame.size = CGSize(width: 600, height: 393)
        let layout = try XCTUnwrap(pages.collectionViewLayout as? ReaderPageLayout)
        layout.itemSize = pages.bounds.size; layout.invalidateLayout(); pages.layoutIfNeeded()
        XCTAssertEqual(seek(1, in: pages), 1)
        layout.reversesPages = false
        layout.invalidateLayout(); pages.layoutIfNeeded()
        XCTAssertEqual(seek(1, in: pages), 1)
    }
    func testStripToMangaAndNormalRestorationClearsThePreviousVerticalOffset() throws {
        let source = Pages()
        let pages = collection(source)
        let layout = try XCTUnwrap(pages.collectionViewLayout as? ReaderPageLayout)
        layout.reversesPages = false; layout.scrollDirection = .vertical
        layout.itemSize = CGSize(width: pages.bounds.width, height: 500)
        layout.invalidateLayout(); pages.layoutIfNeeded()
        pages.setContentOffset(CGPoint(x: 0, y: 600), animated: false)
        XCTAssertGreaterThan(pages.contentOffset.y, 0)
        layout.scrollDirection = .horizontal; layout.reversesPages = true
        layout.itemSize = pages.bounds.size; layout.invalidateLayout()
        XCTAssertEqual(seek(1, in: pages), 1)
        XCTAssertEqual(pages.contentOffset.y, 0, accuracy: 0.01)
        layout.reversesPages = false; layout.invalidateLayout()
        XCTAssertEqual(seek(1, in: pages), 1)
        XCTAssertEqual(pages.contentOffset.y, 0, accuracy: 0.01)
    }
    func testReloadedModesRestoreRealPageFramesBeforeStripOffsetsAreClamped() throws {
        let source = Pages()
        let pages = collection(source)
        pages.delegate = source
        let layout = try XCTUnwrap(pages.collectionViewLayout as? ReaderPageLayout)
        XCTAssertEqual(seek(1, in: pages), 1)
        layout.reversesPages = false
        pages.reloadData()
        layout.prepareForPositionRestore()
        XCTAssertEqual(seek(1, in: pages), 1, "日漫转普通后应显示同一张实际图片")
        layout.scrollDirection = .vertical
        pages.reloadData()
        layout.prepareForPositionRestore()
        let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame)
        let maximum = pages.contentSize.height - pages.bounds.height
        let target = frame.minY + frame.height * 0.4
        XCTAssertGreaterThanOrEqual(maximum, target, "恢复时必须已提交卷轴内容尺寸")
        pages.setContentOffset(CGPoint(x: 0, y: min(maximum, target)), animated: false)
        XCTAssertEqual(pages.contentOffset.y - frame.minY, source.stripHeight * 0.4, accuracy: 0.01)
        XCTAssertEqual(frame.height, source.stripHeight, accuracy: 0.01)
        source.stripHeight = 750
        layout.prepareForPositionRestore()
        let resized = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame)
        pages.setContentOffset(CGPoint(x: 0, y: resized.minY + resized.height * 0.4), animated: false)
        XCTAssertEqual(pages.contentOffset.y - resized.minY, source.stripHeight * 0.4, accuracy: 0.01)
    }
}
