import XCTest
import UIKit
@testable import XXComic

@MainActor
final class ReaderMangaGeometryTests: XCTestCase {
    private final class Pages: NSObject, UICollectionViewDataSource {
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath)
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
        collection.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
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
}
