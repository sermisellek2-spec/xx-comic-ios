import UIKit

@MainActor
final class FilterDrawerNavigationController: UINavigationController, UIViewControllerTransitioningDelegate {
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        FilterDrawerPresentation(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { FilterDrawerAnimation(presenting: true) }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { FilterDrawerAnimation(presenting: false) }
}

@MainActor
private final class FilterDrawerPresentation: UIPresentationController {
    private let backdrop = UIView()
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let bounds = containerView?.bounds else { return .zero }
        let width = max(1, min(bounds.width - 56, 320))
        return CGRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height)
    }
    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(150 / 255)
        backdrop.frame = containerView.bounds; backdrop.alpha = 0
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        containerView.insertSubview(backdrop, at: 0)
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.backdrop.alpha = 0 })
    }
    override func containerViewWillLayoutSubviews() {
        backdrop.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 8
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        presentedView?.clipsToBounds = true
    }
    @objc private func close() { presentedViewController.dismiss(animated: true) }
}

@MainActor
private final class FilterDrawerAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.24 }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key) else { context.completeTransition(false); return }
        let view = controller.view!
        if presenting {
            context.containerView.addSubview(view)
            view.frame = context.finalFrame(for: controller)
            view.transform = CGAffineTransform(translationX: view.bounds.width, y: 0)
        }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            view.transform = self.presenting ? .identity : CGAffineTransform(translationX: view.bounds.width, y: 0)
        }, completion: { _ in context.completeTransition(!context.transitionWasCancelled) })
    }
}
