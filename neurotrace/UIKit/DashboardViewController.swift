import UIKit

@MainActor
final class DashboardViewController: UICollectionViewController {
    nonisolated private enum Section: Hashable, Sendable { case primary, status, shortcuts, notice }
    nonisolated private enum Item: Hashable, Sendable {
        case activeSession(UUID)
        case startSession
        case recentSubject(UUID)
        case subjects
        case completed
        case pencil
        case notice
    }

    private let backend: any AppBackend
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var snapshot: DashboardSnapshot?
    private var pencilObserver: NSObjectProtocol?
    private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
        elementKind: UICollectionView.elementKindSectionHeader
    ) { [weak self] view, _, indexPath in
        guard let section = self?.dataSource.snapshot().sectionIdentifiers[safe: indexPath.section] else { return }
        var content = UIListContentConfiguration.header()
        content.text = switch section {
        case .primary: "当前工作"
        case .status: "研究状态"
        case .shortcuts: "快捷入口"
        case .notice: "说明"
        }
        view.contentConfiguration = content
    }

    var onOpenSubjects: (() -> Void)?
    var onOpenSessions: (() -> Void)?
    var onOpenSubject: ((UUID) -> Void)?
    var onOpenSession: ((UUID) -> Void)?

    init(backend: any AppBackend) {
        self.backend = backend
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        title = "概览"
        navigationItem.largeTitleDisplayMode = .always
        tabBarItem.accessibilityIdentifier = "screen.neurotrace"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let pencilObserver { NotificationCenter.default.removeObserver(pencilObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.accessibilityIdentifier = "screen.neurotrace"
        configureDataSource()
        pencilObserver = NotificationCenter.default.addObserver(
            forName: .pencilMonitorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .activeSession(let id): onOpenSession?(id)
        case .startSession, .completed: onOpenSessions?()
        case .recentSubject(let id): onOpenSubject?(id)
        case .subjects: onOpenSubjects?()
        case .pencil: presentPencilHelp()
        case .notice: break
        }
    }

    private func presentPencilHelp() {
        let message = snapshot?.hasDetectedPencil == true
            ? "已收到真实 Apple Pencil 事件。再次用笔尖触碰、悬停、双击或挤压时，状态会自动更新。"
            : "请将 Apple Pencil 移到屏幕上方或用笔尖轻触此处。应用只在收到真实 Pencil 事件后才会显示已验证；iPadOS 不提供通用的“已连接”查询接口。"
        let alert = UIAlertController(title: "检测 Apple Pencil", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func reload() {
        do {
            snapshot = try backend.dashboard()
            applySnapshot()
        } catch {
            presentError(error, title: "无法载入概览")
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            guard let self, let dashboard = self.snapshot else { return }
            switch item {
            case .activeSession(let id):
                guard dashboard.activeSession?.id == id, let session = dashboard.activeSession else { return }
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "继续测试 · \(session.displayName)",
                    subtitle: activeSessionSubtitle(session),
                    image: "play.circle.fill",
                    tint: .systemTeal
                )
                cell.accessories = [.disclosureIndicator()]
                cell.accessibilityIdentifier = "continue.session"
            case .startSession:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "开始新测试",
                    subtitle: dashboard.subjectCount == 0 ? "请先建立受试者" : "选择受试者与测试模式",
                    image: "plus.circle.fill",
                    tint: .systemTeal
                )
                cell.accessories = [.disclosureIndicator()]
            case .recentSubject:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: dashboard.recentSubject?.code ?? "尚无受试者",
                    subtitle: dashboard.recentSubject.map {
                        "最近更新于 \($0.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                    },
                    image: "person.crop.circle",
                    tint: .systemBlue
                )
                cell.accessories = dashboard.recentSubject == nil ? [] : [.disclosureIndicator()]
            case .subjects:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "受试者",
                    subtitle: "\(dashboard.subjectCount) 位",
                    image: "person.2",
                    tint: .systemBlue
                )
                cell.accessories = [.disclosureIndicator()]
            case .completed:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "已完成测试",
                    subtitle: "\(dashboard.completedSessionCount) 次",
                    image: "checkmark.seal",
                    tint: .systemGreen
                )
                cell.accessories = [.disclosureIndicator()]
            case .pencil:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "Apple Pencil",
                    subtitle: dashboard.pencilStatus,
                    image: dashboard.hasDetectedPencil
                        ? "pencil.tip.crop.circle.badge.checkmark"
                        : "pencil.tip.crop.circle",
                    tint: dashboard.hasDetectedPencil ? .systemGreen : .systemOrange
                )
            case .notice:
                cell.contentConfiguration = UIKitFactory.contentConfiguration(
                    title: "研究用途声明",
                    subtitle: "本工具仅用于神经行为研究数据采集，不提供医学诊断或治疗建议。",
                    image: "info.circle",
                    tint: .secondaryLabel
                )
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        let headerRegistration = headerRegistration
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func applySnapshot() {
        guard let dashboard = snapshot else { return }
        var data = NSDiffableDataSourceSnapshot<Section, Item>()
        data.appendSections([.primary, .status, .shortcuts, .notice])
        if let active = dashboard.activeSession {
            data.appendItems([.activeSession(active.id)], toSection: .primary)
        } else {
            data.appendItems([.startSession], toSection: .primary)
        }
        if let recent = dashboard.recentSubject {
            data.appendItems([.recentSubject(recent.id)], toSection: .status)
        }
        data.appendItems([.pencil], toSection: .status)
        data.appendItems([.subjects, .completed], toSection: .shortcuts)
        data.appendItems([.notice], toSection: .notice)
        dataSource.apply(data, animatingDifferences: true)
    }

    private func activeSessionSubtitle(_ session: SessionSnapshot) -> String {
        var parts = [
            "\(session.completedTaskCount) / \(session.taskCount) 项已完成",
            session.mode.rawValue
        ]
        if let remaining = session.overallRemainingTime() {
            parts.append(remaining >= 0
                ? "整体剩余 \(remaining.neurotraceFormattedDuration)"
                : "超出预计 \((-remaining).neurotraceFormattedDuration)")
        }
        return parts.joined(separator: " · ")
    }
}

nonisolated extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
