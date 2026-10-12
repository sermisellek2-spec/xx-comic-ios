import UIKit

@MainActor
final class ReaderPageLayout: UICollectionViewFlowLayout {
    var reversesPages = false {
        didSet { if oldValue != reversesPages { invalidateLayout() } }
    }
    override var flipsHorizontallyInOppositeLayoutDirection: Bool { false }
    private var usesPagedPages: Bool { scrollDirection == .horizontal }
    func prepareForPositionRestore() {
        // A parent layout callback can precede the collection view's own layout
        // pass. Invalidate delegate sizes and lay out that view before reading
        // frames or clamping a saved strip offset against its content size.
        let context = UICollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutAttributes = true
        context.invalidateFlowLayoutDelegateMetrics = true
        invalidateLayout(with: context)
        collectionView?.setNeedsLayout()
        collectionView?.layoutIfNeeded()
    }
    @discardableResult
    func scrollToLogicalPage(_ index: Int, animated: Bool) -> Bool {
        guard scrollDirection == .horizontal, let collectionView, collectionView.bounds.width > 0 else { return false }
        collectionView.layoutIfNeeded()
        guard let attributes = layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return false }
        // A horizontal scrollToItem option can retain the previous strip's Y
        // offset. Restore both axes against the actual logical page frame.
        collectionView.setContentOffset(CGPoint(x: attributes.frame.minX, y: 0), animated: animated)
        return true
    }
    override var collectionViewContentSize: CGSize {
        guard usesPagedPages, let collectionView else { return super.collectionViewContentSize }
        guard collectionView.numberOfSections > 0 else { return .zero }
        return CGSize(width: CGFloat(collectionView.numberOfItems(inSection: 0)) * collectionView.bounds.width,
                      height: collectionView.bounds.height)
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard usesPagedPages else { return super.layoutAttributesForItem(at: indexPath) }
        guard let collectionView, collectionView.numberOfSections > 0, indexPath.section == 0,
              (0..<collectionView.numberOfItems(inSection: 0)).contains(indexPath.item) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let physicalPage = reversesPages ? collectionView.numberOfItems(inSection: 0) - 1 - indexPath.item : indexPath.item
        attributes.frame = CGRect(x: CGFloat(physicalPage) * collectionView.bounds.width, y: 0,
                                  width: collectionView.bounds.width, height: collectionView.bounds.height)
        return attributes
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard usesPagedPages else { return super.layoutAttributesForElements(in: rect) }
        guard let collectionView, collectionView.numberOfSections > 0,
              collectionView.bounds.width > 0, !rect.isNull else { return [] }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return [] }
        let first = Int(max(0, min(CGFloat(count), floor(rect.minX / collectionView.bounds.width))))
        let last = Int(min(CGFloat(count - 1), max(-1, floor(rect.maxX / collectionView.bounds.width))))
        guard first <= last else { return [] }
        return (first...last).compactMap { physicalPage in
            let logicalPage = reversesPages ? count - 1 - physicalPage : physicalPage
            guard let attributes = layoutAttributesForItem(at: IndexPath(item: logicalPage, section: 0)),
                  attributes.frame.intersects(rect) else { return nil }
            return attributes
        }
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return true }
        return newBounds.size != collectionView.bounds.size || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}
