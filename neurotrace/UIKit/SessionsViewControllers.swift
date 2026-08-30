import UIKit

@MainActor
final class SessionsViewController: UICollectionViewController, UISearchResultsUpdating, UISearchBarDelegate {
    nonisolated private enum Section: Hashable, Sendable { case main }
    private let backend: any AppBackend
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!
    private var sessionsByID: [UUID: SessionSnapshot] = [:]
    private var filter: SessionFilter = .all
    private var query = ""
    var onOpenSession: ((UUID) -> Void)?

    init(backend: any AppBackend) {
        self.backend = backend
        let configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        title = "测试"
        navigationItem.largeTitleDisplayMode = .always
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.accessibilityIdentifier = "screen.测试"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add,
            primaryAction: UIAction { [weak self] _ in self?.presentNewSession() }
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "session.add"

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索测试名称或受试者"
        search.searchBar.scopeButtonTitles = SessionFilter.allCases.map(\.title)
        search.searchBar.selectedScopeButtonIndex = filter.rawValue
        search.searchBar.showsScopeBar = true
        search.searchBar.delegate = self
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }

    func searchBar(
        _ searchBar: UISearchBar,
        selectedScopeButtonIndexDidChange selectedScope: Int
    ) {
        guard let value = SessionFilter(rawValue: selectedScope) else { return }
        filter = value
        reload()
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onOpenSession?(id)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let session = sessionsByID[id] else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            var actions: [UIMenuElement] = [
                UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { _ in self?.rename(session) }
            ]
            if session.state == .completed {
                actions.append(UIAction(title: "导出", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.export(session)
                })
            }
            actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(session)
            })
            return UIMenu(children: actions)
        })
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> {
            [weak self] cell, _, id in
            guard let session = self?.sessionsByID[id] else { return }
            cell.contentConfiguration = UIKitFactory.contentConfiguration(
                title: session.displayName,
                subtitle: "\(session.subjectCode) · \(session.mode.rawValue) · \(session.state.title) · \(session.completedTaskCount)/\(session.taskCount)",
                image: session.state == .completed ? "checkmark.seal.fill" : "list.clipboard",
                tint: self?.tint(for: session.state) ?? .systemTeal
            )
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = "session.row.\(id.uuidString)"
            if session.state == .inProgress || session.state == .ready {
                cell.accessibilityIdentifier = "continue.session.row"
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func reload() {
        do {
            let sessions = try backend.sessions(filter: filter, matching: query)
            sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
            snapshot.appendSections([.main])
            snapshot.appendItems(sessions.map(\.id))
            dataSource.apply(snapshot, animatingDifferences: true)
            contentUnavailableConfiguration = sessions.isEmpty
                ? UIKitFactory.emptyConfiguration(
                    title: query.isEmpty ? "暂无测试" : "没有匹配结果",
                    message: query.isEmpty ? "创建测试后，可在此继续采集或查看历史记录。" : "请调整搜索词或筛选条件。",
                    symbol: query.isEmpty ? "list.clipboard" : "magnifyingglass",
                    buttonTitle: query.isEmpty ? "新建测试" : nil,
                    action: query.isEmpty ? UIAction { [weak self] _ in self?.presentNewSession() } : nil
                ) : nil
        } catch {
            presentError(error, title: "无法载入测试")
        }
    }

    private func presentNewSession() {
        let controller = NewSessionViewController(backend: backend)
        controller.onCreated = { [weak self] id in
            self?.dismiss(animated: true) {
                self?.reload()
                self?.onOpenSession?(id)
            }
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func rename(_ session: SessionSnapshot) {
        presentTextPrompt(
            title: "重命名测试",
            message: "留空将恢复显示受试者编号。",
            value: session.hasCustomName ? session.displayName : "",
            placeholder: "例如：上午复测"
        ) { [weak self] name in
            do {
                try self?.backend.renameSession(id: session.id, name: name)
                self?.reload()
            } catch {
                self?.presentError(error)
            }
        }
    }

    private func export(_ session: SessionSnapshot) {
        Task { @MainActor in
            do {
                presentShareSheet(url: try await backend.exportSession(id: session.id))
            } catch {
                presentError(error)
            }
        }
    }

    private func confirmDelete(_ session: SessionSnapshot) {
        let alert = UIAlertController(
            title: "删除本次测试？",
            message: "原始点、点击事件、预览和特征数据会一并删除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.backend.deleteSession(id: session.id)
                    self.reload()
                } catch {
                    self.presentError(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func tint(for state: SessionState) -> UIColor {
        switch state {
        case .ready, .inProgress: .systemTeal
        case .completed: .systemGreen
        case .abandoned: .systemRed
        }
    }
}

@MainActor
final class NewSessionViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case subject, mode, summary }
    private let backend: any AppBackend
    private var subjects: [SubjectSnapshot] = []
    private var selectedSubjectID: UUID?
    private var mode: TestMode = .full
    var onCreated: ((UUID) -> Void)?

    init(backend: any AppBackend) {
        self.backend = backend
        super.init(style: .insetGrouped)
        title = "新建测试"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "创建",
            style: .prominent,
            target: self,
            action: #selector(create)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "session.create"
        do {
            subjects = try backend.subjects(matching: "")
            selectedSubjectID = subjects.first?.id
            navigationItem.rightBarButtonItem?.isEnabled = selectedSubjectID != nil
        } catch {
            presentError(error)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .subject: 1
        case .mode: TestMode.allCases.count
        case .summary: 4
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .subject: "受试者"
        case .mode: "测试模式"
        case .summary: "本次测试"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .subject:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "研究编号"
            let selected = subjects.first { $0.id == selectedSubjectID }
            cell.detailTextLabel?.text = selected?.code ?? "请选择"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        case .mode:
            let option = TestMode.allCases[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = option.rawValue
            cell.detailTextLabel?.text = option == .quick
                ? "6 项核心任务 · \(option.estimatedDuration)"
                : "完整 11 项研究任务 · \(option.estimatedDuration)"
            cell.accessoryType = option == mode ? .checkmark : .none
            return cell
        case .summary:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let hand = subjects.first { $0.id == selectedSubjectID }?.dominantHand ?? .unspecified
            let rows: [(String, String)] = [
                ("任务数量", "\(TaskCatalog.tasks(for: mode, dominantHand: hand).count)"),
                ("整体倒计时", mode.overallDuration.neurotraceFormattedDuration),
                ("预计用时", mode.estimatedDuration),
                ("单手任务", "\(TaskCatalog.singleHand(for: hand).rawValue)手")
            ]
            cell.textLabel?.text = rows[indexPath.row].0
            cell.detailTextLabel?.text = rows[indexPath.row].1
            cell.selectionStyle = .none
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .subject:
            presentSubjectPicker(from: tableView.cellForRow(at: indexPath))
        case .mode:
            mode = TestMode.allCases[indexPath.row]
            tableView.reloadSections(IndexSet([Section.mode.rawValue, Section.summary.rawValue]), with: .automatic)
        case .summary, .none:
            break
        }
    }

    private func presentSubjectPicker(from source: UIView?) {
        let selected = subjects.first { $0.id == selectedSubjectID }
        let alert = UIAlertController(
            title: "选择受试者",
            message: selected.map { "当前：\($0.code)" },
            preferredStyle: .actionSheet
        )
        subjects.forEach { subject in
            alert.addAction(UIAlertAction(title: subject.code, style: .default) { [weak self] _ in
                self?.selectedSubjectID = subject.id
                self?.navigationItem.rightBarButtonItem?.isEnabled = true
                self?.tableView.reloadSections(
                    IndexSet([Section.subject.rawValue, Section.summary.rawValue]),
                    with: .none
                )
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = source ?? view
        alert.popoverPresentationController?.sourceRect = source?.bounds ?? CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        present(alert, animated: true)
    }

    @objc private func create() {
        guard let selectedSubjectID else { return }
        do {
            onCreated?(try backend.createSession(subjectID: selectedSubjectID, mode: mode))
        } catch {
            presentError(error, title: "无法创建测试")
        }
    }
}

@MainActor
final class SessionDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case overview, analysis, tasks }
    private let sessionID: UUID
    private let backend: any AppBackend
    private var detail: SessionDetailSnapshot?
    private var countdownTimer: Timer?
    var onChanged: (() -> Void)?

    init(sessionID: UUID, backend: any AppBackend) {
        self.sessionID = sessionID
        self.backend = backend
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { countdownTimer?.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "session.detail"
        navigationItem.largeTitleDisplayMode = .never
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        startCountdownTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    override func numberOfSections(in tableView: UITableView) -> Int { detail == nil ? 0 : Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let detail, let value = Section(rawValue: section) else { return 0 }
        switch value {
        case .overview: return 4
        case .analysis: return 1
        case .tasks: return detail.tasks.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .overview: "测试信息"
        case .analysis: "分析报告"
        case .tasks: "采集任务"
        case .none: nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let detail, let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch section {
        case .overview:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let rows = [
                ("受试者", detail.session.subjectCode),
                ("模式", detail.session.mode.rawValue),
                ("进度", "\(detail.session.completedTaskCount)/\(detail.session.taskCount) · \(detail.session.state.title)"),
                ("整体倒计时", overallCountdownText(for: detail.session))
            ]
            cell.textLabel?.text = rows[indexPath.row].0
            cell.detailTextLabel?.text = rows[indexPath.row].1
            cell.selectionStyle = .none
            return cell
        case .analysis:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if let report = detail.analysisReport {
                cell.textLabel?.text = report.summary.isEmpty ? "查看分析报告" : report.summary
                cell.detailTextLabel?.text = "\(report.status.rawValue) · \(report.overallRiskLevel.rawValue)"
                cell.imageView?.image = UIImage(systemName: "doc.text.magnifyingglass")
            } else if detail.session.state == .completed {
                cell.textLabel?.text = "生成分析报告"
                cell.detailTextLabel?.text = "本地模型优先，已配置时补充大模型分析"
                cell.imageView?.image = UIImage(systemName: "wand.and.stars")
            } else {
                cell.textLabel?.text = "完成全部任务后生成报告"
                cell.detailTextLabel?.text = nil
                cell.imageView?.image = UIImage(systemName: "doc.text")
                cell.selectionStyle = .none
            }
            cell.accessoryType = .disclosureIndicator
            return cell
        case .tasks:
            let task = detail.tasks[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = "\(task.orderIndex + 1). \(task.title)"
            content.secondaryText = "\(task.hand.rawValue) · \(task.state.title)" + (task.state == .completed ? " · \(task.duration.neurotraceFormattedDuration)" : "")
            content.image = UIImage(systemName: task.state == .completed ? "checkmark.circle.fill" : "circle")
            content.imageProperties.tintColor = task.state == .completed ? .systemGreen : .systemTeal
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = task.title
            cell.accessibilityValue = task.state.title
            if task.state != .completed, task.id == currentTask?.id {
                cell.accessibilityIdentifier = "continue.current-task"
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let detail, let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .overview: break
        case .analysis:
            if let report = detail.analysisReport {
                navigationController?.pushViewController(AnalysisReportViewController(report: report), animated: true)
            } else if detail.session.state == .completed {
                analyze(force: true)
            }
        case .tasks:
            let task = detail.tasks[indexPath.row]
            if task.state == .completed {
                navigationController?.pushViewController(
                    TaskRecordDetailViewController(task: task, backend: backend),
                    animated: true
                )
            } else if task.id == currentTask?.id, detail.session.state != .abandoned {
                presentRunner(taskID: task.id)
            }
        }
    }

    private var currentTask: TaskSnapshot? {
        detail?.tasks.first { $0.state != .completed }
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.detail?.session.startedAt != nil,
                      self.tableView.numberOfSections > Section.overview.rawValue,
                      self.tableView.numberOfRows(inSection: Section.overview.rawValue) > 3
                else { return }
                self.tableView.reloadRows(
                    at: [IndexPath(row: 3, section: Section.overview.rawValue)],
                    with: .none
                )
            }
        }
    }

    private func overallCountdownText(for session: SessionSnapshot) -> String {
        guard let remaining = session.overallRemainingTime() else {
            return "首项任务开始后计时"
        }
        if session.state == .completed || session.state == .abandoned {
            return "已结束"
        }
        return remaining >= 0
            ? "剩余 \(remaining.neurotraceFormattedDuration)"
            : "超出预计 \((-remaining).neurotraceFormattedDuration)"
    }

    private func reload() {
        do {
            guard let value = try backend.sessionDetail(id: sessionID) else {
                navigationController?.popViewController(animated: true)
                return
            }
            detail = value
            title = value.session.displayName
            configureMenu(for: value)
            tableView.reloadData()
            refreshControl?.endRefreshing()
        } catch {
            refreshControl?.endRefreshing()
            presentError(error, title: "无法载入测试")
        }
    }

    private func configureMenu(for detail: SessionDetailSnapshot) {
        var children: [UIMenuElement] = [
            UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.rename() }
        ]
        if detail.session.state == .completed {
            children.append(UIAction(title: "重新分析", image: UIImage(systemName: "wand.and.stars")) { [weak self] _ in
                self?.analyze(force: true)
            })
            children.append(UIAction(title: "导出研究数据", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.export()
            })
        } else if detail.session.state != .abandoned {
            children.append(UIAction(title: "放弃测试", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                self?.confirmAbandon()
            })
        }
        children.append(UIAction(title: "删除测试", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirmDelete()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: children)
        )
    }

    private func presentRunner(taskID: UUID) {
        do {
            let runner = try backend.makeTaskRunner(sessionID: sessionID, taskID: taskID)
            let controller = TaskRunnerViewController(runner: runner)
            controller.onFinished = { [weak self] in self?.reload(); self?.onChanged?() }
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .fullScreen
            present(navigation, animated: true)
        } catch {
            presentError(error, title: "无法开始采集")
        }
    }

    private func analyze(force: Bool) {
        let progress = UIActivityIndicatorView(style: .medium)
        progress.startAnimating()
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: progress)
        Task { @MainActor in
            defer { navigationItem.leftBarButtonItem = nil }
            do {
                let report = try await backend.analyzeSession(id: sessionID, force: force)
                reload()
                navigationController?.pushViewController(AnalysisReportViewController(report: report), animated: true)
            } catch {
                presentError(error, title: "无法生成分析")
            }
        }
    }

    private func rename() {
        guard let session = detail?.session else { return }
        presentTextPrompt(
            title: "重命名测试",
            message: "留空将恢复显示受试者编号。",
            value: session.hasCustomName ? session.displayName : "",
            placeholder: "例如：上午复测"
        ) { [weak self] name in
            guard let self else { return }
            do {
                try backend.renameSession(id: sessionID, name: name)
                reload()
                onChanged?()
            } catch { presentError(error) }
        }
    }

    private func export() {
        Task { @MainActor in
            do { presentShareSheet(url: try await backend.exportSession(id: sessionID)) }
            catch { presentError(error, title: "导出失败") }
        }
    }

    private func confirmAbandon() {
        let alert = UIAlertController(title: "放弃这次测试？", message: "已完成的任务数据会保留。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "放弃", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try backend.abandonSession(id: sessionID); reload(); onChanged?() }
            catch { presentError(error) }
        })
        present(alert, animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "删除这次测试？", message: "原始采集文件和报告会一并删除。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.backend.deleteSession(id: self.sessionID)
                    self.onChanged?()
                    self.navigationController?.popViewController(animated: true)
                } catch { self.presentError(error) }
            }
        })
        present(alert, animated: true)
    }
}

@MainActor
final class TaskRecordDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case preview, summary, features, quality }
    private let task: TaskSnapshot
    private let backend: any AppBackend
    private var preview: UIImage?
    private let featurePairs: [(String, Double)]

    init(task: TaskSnapshot, backend: any AppBackend) {
        self.task = task
        self.backend = backend
        featurePairs = task.featureValues.sorted { $0.key < $1.key }
        super.init(style: .insetGrouped)
        title = task.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        Task { @MainActor in
            if let url = await backend.previewURL(taskID: task.id), let image = UIImage(contentsOfFile: url.path) {
                preview = image
                tableView.reloadSections(IndexSet(integer: Section.preview.rawValue), with: .automatic)
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .preview: task.hasPreview ? 1 : 0
        case .summary: 5
        case .features: max(1, featurePairs.count)
        case .quality: max(1, task.qualityFlags.count)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .preview: "采集预览"
        case .summary: "原始数据"
        case .features: "特征"
        case .quality: "质量提示"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .preview:
            let cell = UITableViewCell()
            let imageView = UIImageView(image: preview)
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .tertiaryLabel
            imageView.image = preview ?? UIImage(systemName: "photo")
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                imageView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
                imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
                imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 360)
            ])
            cell.selectionStyle = .none
            return cell
        case .summary:
            let rows = [
                ("手别", task.hand.rawValue),
                ("采集点", "\(task.sampleCount)"),
                ("点击事件", "\(task.tapCount)"),
                ("持续时间", task.duration.neurotraceFormattedDuration),
                ("采集次数", "\(task.attemptCount)")
            ]
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = rows[indexPath.row].0
            cell.detailTextLabel?.text = rows[indexPath.row].1
            cell.selectionStyle = .none
            return cell
        case .features:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            if featurePairs.isEmpty {
                cell.textLabel?.text = "暂无可用特征"
            } else {
                let pair = featurePairs[indexPath.row]
                cell.textLabel?.text = pair.0
                cell.detailTextLabel?.text = pair.1.formatted(.number.precision(.fractionLength(0...4)))
            }
            cell.selectionStyle = .none
            return cell
        case .quality:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = task.qualityFlags.isEmpty ? "未发现质量问题" : task.qualityFlags[indexPath.row]
            cell.imageView?.image = UIImage(systemName: task.qualityFlags.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
            cell.imageView?.tintColor = task.qualityFlags.isEmpty ? .systemGreen : .systemOrange
            cell.selectionStyle = .none
            return cell
        }
    }
}

@MainActor
final class AnalysisReportViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case overview, warnings, tasks }
    private let report: SessionAnalysisReport

    init(report: SessionAnalysisReport) {
        self.report = report
        super.init(style: .insetGrouped)
        title = "分析报告"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            menu: UIMenu(children: [
                UIAction(title: "结果仅供研究，不用于诊断", attributes: .disabled) { _ in }
            ])
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .overview: 3
        case .warnings: max(1, report.warnings.count)
        case .tasks: report.taskReports.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .overview: "概要"
        case .warnings: "提示"
        case .tasks: "任务分析"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .overview:
            let cell = UITableViewCell(style: indexPath.row == 2 ? .subtitle : .value1, reuseIdentifier: nil)
            if indexPath.row == 0 {
                cell.textLabel?.text = "整体关注级别"
                cell.detailTextLabel?.text = report.overallRiskLevel.rawValue
                cell.detailTextLabel?.textColor = color(for: report.overallRiskLevel)
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "分析状态"
                cell.detailTextLabel?.text = report.status.rawValue
            } else {
                cell.textLabel?.text = report.summary
                cell.detailTextLabel?.text = "生成于 \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))"
                cell.textLabel?.numberOfLines = 0
            }
            cell.selectionStyle = .none
            return cell
        case .warnings:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = report.warnings.isEmpty ? "无附加警告" : report.warnings[indexPath.row]
            cell.textLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(systemName: report.warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
            cell.imageView?.tintColor = report.warnings.isEmpty ? .systemGreen : .systemOrange
            cell.selectionStyle = .none
            return cell
        case .tasks:
            let value = report.taskReports[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = value.title
            cell.detailTextLabel?.text = "\(value.hand) · \(value.riskLevel.rawValue)" + (value.notes.first.map { " · \($0)" } ?? "")
            cell.detailTextLabel?.numberOfLines = 2
            cell.imageView?.image = UIImage(systemName: "waveform.path.ecg")
            cell.imageView?.tintColor = color(for: value.riskLevel)
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .tasks else { return }
        navigationController?.pushViewController(
            TaskAnalysisDetailViewController(report: report.taskReports[indexPath.row]),
            animated: true
        )
    }

    private func color(for level: RiskLevel) -> UIColor {
        switch level {
        case .low: .systemGreen
        case .medium: .systemOrange
        case .high: .systemRed
        case .unknown: .secondaryLabel
        }
    }
}

@MainActor
private final class TaskAnalysisDetailViewController: UITableViewController {
    private let report: TaskAnalysisReport
    private let features: [(String, Double)]

    init(report: TaskAnalysisReport) {
        self.report = report
        features = report.featureHighlights.sorted { $0.key < $1.key }
        super.init(style: .insetGrouped)
        title = report.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: 2
        case 1: max(1, features.count)
        default: max(1, report.localModelResults.count + report.largeModelResults.count + report.notes.count)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["评估", "特征摘要", "模型结果与备注"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "关注级别"
                cell.detailTextLabel?.text = report.riskLevel.rawValue
            } else {
                cell.textLabel?.text = "风险分数"
                cell.detailTextLabel?.text = report.riskScore?.formatted(.number.precision(.fractionLength(1))) ?? "无法评估"
            }
        } else if indexPath.section == 1 {
            if features.isEmpty {
                cell.textLabel?.text = "暂无特征摘要"
            } else {
                cell.textLabel?.text = features[indexPath.row].0
                cell.detailTextLabel?.text = features[indexPath.row].1.formatted(.number.precision(.fractionLength(0...4)))
            }
        } else {
            let localCount = report.localModelResults.count
            let remoteCount = report.largeModelResults.count
            if indexPath.row < localCount {
                let item = report.localModelResults[indexPath.row]
                cell.textLabel?.text = item.modelName
                cell.detailTextLabel?.text = item.errorMessage ?? item.summary
            } else if indexPath.row < localCount + remoteCount {
                let item = report.largeModelResults[indexPath.row - localCount]
                cell.textLabel?.text = item.userFacingTitle
                cell.detailTextLabel?.text = item.errorMessage ?? item.summary
            } else if !report.notes.isEmpty {
                cell.textLabel?.text = report.notes[indexPath.row - localCount - remoteCount]
            } else {
                cell.textLabel?.text = "暂无模型结果"
            }
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
        }
        return cell
    }
}
