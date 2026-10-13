import UIKit

@MainActor
final class FilterDrawerNavigationController: UINavigationController, UIViewControllerTransitioningDelegate {
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        modalPresentationStyle = .custom
        transitioningDelegate = self
        setNavigationBarHidden(true, animated: false)
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
        let safe = containerView?.safeAreaInsets ?? .zero
        let requested = presentedViewController.preferredContentSize.height
        let contentHeight = requested > 0 ? max(220, requested) : min(400, bounds.height * 0.62)
        let height = min(bounds.height - safe.top - 12, contentHeight + safe.bottom)
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }
    override func presentationTransitionWillBegin() {
        if presentedViewController.overrideUserInterfaceStyle == .unspecified {
            presentedViewController.overrideUserInterfaceStyle = presentingViewController.overrideUserInterfaceStyle
        }
        guard let containerView else { return }
        backdrop.backgroundColor = UIColor(red: 10 / 255, green: 24 / 255, blue: 37 / 255, alpha: 145 / 255)
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
        presentedView?.layer.cornerRadius = 16
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.clipsToBounds = true
    }
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        containerView?.setNeedsLayout()
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
            view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            view.transform = self.presenting ? .identity : CGAffineTransform(translationX: 0, y: view.bounds.height)
        }, completion: { _ in context.completeTransition(!context.transitionWasCancelled) })
    }
}
