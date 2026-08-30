import UIKit
import OSLog

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "top.hadal.neurotrace", category: "Lifecycle")
    var window: UIWindow?
    private var dependencies: DependencyContainer?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        logger.notice("UIKit scene delegate connecting")
        guard let windowScene = scene as? UIWindowScene else { return }
        do {
            let dependencies = try DependencyContainer()
            try dependencies.backend.bootstrap()
            let coordinator = AppCoordinator(backend: dependencies.backend)
            let window = PencilTrackingWindow(windowScene: windowScene)
            window.onPencilDetection = { [weak monitor = dependencies.services.pencilMonitor] source in
                monitor?.record(source)
            }
            window.tintColor = .systemTeal
            window.rootViewController = coordinator.rootViewController
            window.makeKeyAndVisible()
            self.dependencies = dependencies
            self.coordinator = coordinator
            self.window = window
            logger.notice("UIKit root window is visible")
        } catch {
            logger.fault("UIKit bootstrap failed: \(error.localizedDescription, privacy: .public)")
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            controller.contentUnavailableConfiguration = {
                var configuration = UIContentUnavailableConfiguration.empty()
                configuration.image = UIImage(systemName: "exclamationmark.triangle")
                configuration.text = "无法启动 neurotrace"
                configuration.secondaryText = error.localizedDescription
                return configuration
            }()
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            self.window = window
        }
    }
}
