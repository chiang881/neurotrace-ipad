import UIKit
import OSLog

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private let logger = Logger(subsystem: "top.hadal.neurotrace", category: "Lifecycle")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let staleSessions = application.openSessions.filter { session in
            session.configuration.delegateClass != SceneDelegate.self
        }
        logger.notice(
            "UIKit application delegate launched; stale scenes: \(staleSessions.count, privacy: .public)"
        )

        // A scene session created by the former SwiftUI lifecycle can survive an
        // app update and reconnect to SwiftUI's private scene delegate. That
        // leaves the UIKit rewrite with no window and produces a black screen.
        // Create the replacement first, then retire only those legacy sessions.
        if !staleSessions.isEmpty {
            application.requestSceneSessionActivation(
                nil,
                userActivity: nil,
                options: nil
            ) { [logger] error in
                logger.error("Unable to activate replacement UIKit scene: \(error.localizedDescription, privacy: .public)")
            }
            staleSessions.forEach { session in
                application.requestSceneSessionDestruction(session, options: nil) { [logger] error in
                    logger.error("Unable to discard legacy scene: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        logger.notice("Creating UIKit scene configuration")
        let configuration = UISceneConfiguration(
            name: "neurotrace UIKit 2",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
