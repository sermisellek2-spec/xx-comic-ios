import UIKit
import ComicCore

@MainActor
extension UIViewController {
    func showSourceManagement(environment: AppEnvironment, onVerified: @escaping () -> Void) {
        guard presentedViewController == nil else { return }
        let controller = SourceSettingsViewController(environment: environment, onVerified: onVerified)
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in
            navigation?.dismiss(animated: true)
        })
        present(navigation, animated: true)
    }

    func showSourceError(_ error: Error, environment: AppEnvironment, retry: @escaping () -> Void) {
        guard (error as? Mh18SourceError) == .verificationRequired else { showError(error); return }
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "需要验证", message: "请先完成站点验证", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去验证", style: .default) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { [weak self] in
                self?.showSourceManagement(environment: environment, onVerified: retry)
            }
        })
        present(alert, animated: true)
    }
}
