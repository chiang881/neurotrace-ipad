import UIKit

nonisolated enum AppSection: String, CaseIterable, Hashable, Sendable {
    case dashboard
    case subjects
    case sessions
    case settings

    var title: String {
        switch self {
        case .dashboard: "概览"
        case .subjects: "受试者"
        case .sessions: "测试"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .subjects: "person.2"
        case .sessions: "list.clipboard"
        case .settings: "gearshape"
        }
    }

    var accessibilityIdentifier: String { "sidebar.\(rawValue)" }
}

@MainActor
final class AppCoordinator {
    let rootViewController: UIViewController
    private let backend: any AppBackend
    private let tabBarController: UITabBarController
    private var navigationControllers: [AppSection: UINavigationController] = [:]
    private var tabs: [AppSection: UITab] = [:]

    init(backend: any AppBackend) {
        self.backend = backend
        tabBarController = UITabBarController()
        rootViewController = tabBarController

        configureTabs()
        tabBarController.mode = .tabSidebar
        tabBarController.sidebar.preferredLayout = .tile
        tabBarController.compactTabIdentifiers = AppSection.allCases.map(\.rawValue)
        tabBarController.customizationIdentifier = "NeuroTracePrimaryNavigation"
        tabBarController.tabBarMinimizeBehavior = .automatic
        select(.dashboard)
    }

    private func configureTabs() {
        let values = AppSection.allCases.map { section in
            let navigation = UINavigationController(rootViewController: makeRootController(for: section))
            navigation.navigationBar.prefersLargeTitles = true
            navigationControllers[section] = navigation

            let tab = UITab(
                title: section.title,
                image: UIImage(systemName: section.symbol),
                identifier: section.rawValue
            ) { _ in
                navigation
            }
            tab.preferredPlacement = .fixed
            tab.allowsHiding = false
            tab.accessibilityIdentifier = section.accessibilityIdentifier
            tabs[section] = tab
            return tab
        }
        tabBarController.tabs = values
    }

    private func makeRootController(for section: AppSection) -> UIViewController {
        switch section {
        case .dashboard:
            let dashboard = DashboardViewController(backend: backend)
            dashboard.onOpenSubjects = { [weak self] in self?.select(.subjects) }
            dashboard.onOpenSessions = { [weak self] in self?.select(.sessions) }
            dashboard.onOpenSubject = { [weak self] id in self?.showSubject(id: id) }
            dashboard.onOpenSession = { [weak self] id in self?.showSession(id: id) }
            return dashboard
        case .subjects:
            let subjects = SubjectsViewController(backend: backend)
            subjects.onOpenSubject = { [weak self] id in self?.showSubject(id: id) }
            return subjects
        case .sessions:
            let sessions = SessionsViewController(backend: backend)
            sessions.onOpenSession = { [weak self] id in self?.showSession(id: id) }
            return sessions
        case .settings:
            return SettingsViewController(backend: backend)
        }
    }

    private func select(_ section: AppSection) {
        guard let tab = tabs[section] else { return }
        tabBarController.selectedTab = tab
        navigationControllers[section]?.popToRootViewController(animated: false)
    }

    private func showSubject(id: UUID) {
        select(.subjects)
        let controller = SubjectDetailViewController(backend: backend, subjectID: id)
        controller.onOpenSession = { [weak self] sessionID in self?.showSession(id: sessionID) }
        navigationControllers[.subjects]?.pushViewController(controller, animated: true)
    }

    private func showSession(id: UUID) {
        select(.sessions)
        let controller = SessionDetailViewController(sessionID: id, backend: backend)
        navigationControllers[.sessions]?.pushViewController(controller, animated: true)
    }
}
