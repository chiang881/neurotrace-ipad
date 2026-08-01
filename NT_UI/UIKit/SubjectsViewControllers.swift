import UIKit

@MainActor
final class SubjectsViewController: UICollectionViewController, UISearchResultsUpdating {
    nonisolated private enum Section: Hashable, Sendable { case main }
    private let backend: any AppBackend
    private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>!
    private var subjectsByID: [UUID: SubjectSnapshot] = [:]
    private var query = ""
    var onOpenSubject: ((UUID) -> Void)?

    init(backend: any AppBackend) {
        self.backend = backend
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.trailingSwipeActionsConfigurationProvider = nil
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        title = "受试者"
        navigationItem.largeTitleDisplayMode = .always
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.accessibilityIdentifier = "screen.受试者"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add,
            primaryAction: UIAction { [weak self] _ in self?.presentEditor(subject: nil) }
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "subject.add"
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索研究编号"
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

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onOpenSubject?(id)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let subject = subjectsByID[id] else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { _ in
                    self?.presentEditor(subject: subject)
                },
                UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.confirmDelete(subject)
                }
            ])
        })
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> {
            [weak self] cell, _, id in
            guard let subject = self?.subjectsByID[id] else { return }
            let details = [
                subject.age.map { "\($0) 岁" },
                subject.dominantHand == .unspecified ? nil : subject.dominantHand.rawValue,
                subject.researchGroup.rawValue,
                "\(subject.sessionCount) 次测试"
            ].compactMap { $0 }.joined(separator: " · ")
            cell.contentConfiguration = UIKitFactory.contentConfiguration(
                title: subject.code,
                subtitle: details,
                image: "person.crop.circle",
                tint: .systemTeal
            )
            cell.accessories = [.disclosureIndicator()]
            cell.accessibilityIdentifier = "subject.row.\(subject.id.uuidString)"
        }
        dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) {
            collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func reload() {
        do {
            let subjects = try backend.subjects(matching: query)
            subjectsByID = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0) })
            var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
            snapshot.appendSections([.main])
            snapshot.appendItems(subjects.map(\.id))
            dataSource.apply(snapshot, animatingDifferences: true)
            contentUnavailableConfiguration = subjects.isEmpty
                ? UIKitFactory.emptyConfiguration(
                    title: query.isEmpty ? "尚无受试者" : "没有匹配结果",
                    message: query.isEmpty ? "新增研究编号后即可创建测试。" : "请尝试其他研究编号。",
                    symbol: query.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                    buttonTitle: query.isEmpty ? "新增受试者" : nil,
                    action: query.isEmpty ? UIAction { [weak self] _ in self?.presentEditor(subject: nil) } : nil
                ) : nil
        } catch {
            presentError(error, title: "无法载入受试者")
        }
    }

    private func presentEditor(subject: SubjectSnapshot?) {
        let controller = SubjectEditorViewController(backend: backend, subject: subject)
        controller.onSaved = { [weak self] in self?.reload() }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func confirmDelete(_ subject: SubjectSnapshot) {
        let alert = UIAlertController(
            title: "删除 \(subject.code)？",
            message: "该受试者的测试和本地原始数据会一并删除，无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.backend.deleteSubject(id: subject.id)
                    self.reload()
                } catch {
                    self.presentError(error)
                }
            }
        })
        present(alert, animated: true)
    }
}

@MainActor
final class SubjectEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case identity, demographics, notes }
    private let backend: any AppBackend
    private let subject: SubjectSnapshot?
    private let codeField = UITextField()
    private let ageField = UITextField()
    private let notesView = UITextView()
    private var sex: SubjectSex
    private var hand: DominantHand
    private var group: ResearchGroup
    var onSaved: (() -> Void)?

    init(backend: any AppBackend, subject: SubjectSnapshot?) {
        self.backend = backend
        self.subject = subject
        sex = subject?.sex ?? .unspecified
        hand = subject?.dominantHand ?? .unspecified
        group = subject?.researchGroup ?? .unknown
        super.init(style: .insetGrouped)
        title = subject == nil ? "新增受试者" : "编辑受试者"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.keyboardDismissMode = .interactive
        codeField.text = subject?.code
        codeField.placeholder = "例如 S001"
        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.accessibilityIdentifier = "subject.code"
        ageField.text = subject?.age.map(String.init)
        ageField.placeholder = "可选"
        ageField.keyboardType = .numberPad
        notesView.text = subject?.notes
        notesView.font = .preferredFont(forTextStyle: .body)
        notesView.adjustsFontForContentSizeCategory = true
        notesView.accessibilityLabel = "备注"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "保存",
            primaryAction: UIAction { [weak self] _ in self?.save() }
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .identity: 2
        case .demographics: 3
        case .notes: 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .identity: "研究信息"
        case .demographics: "分组信息"
        case .notes: "备注"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        if section == .notes {
            let cell = UITableViewCell()
            notesView.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(notesView)
            NSLayoutConstraint.activate([
                notesView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                notesView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                notesView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                notesView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                notesView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
            ])
            return cell
        }
        if section == .identity {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let field = indexPath.row == 0 ? codeField : ageField
            var content = cell.defaultContentConfiguration()
            content.text = indexPath.row == 0 ? "研究编号" : "年龄"
            cell.contentConfiguration = content
            field.textAlignment = .right
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                field.widthAnchor.constraint(equalToConstant: 220),
                field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            return cell
        }
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let values: [(String, String)] = [
            ("性别", sex.rawValue),
            ("惯用手", hand.rawValue),
            ("分组", group.rawValue)
        ]
        let value = values[indexPath.row]
        cell.textLabel?.text = value.0
        cell.detailTextLabel?.text = value.1
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .identity:
            (indexPath.row == 0 ? codeField : ageField).becomeFirstResponder()
        case .demographics:
            let source = tableView.cellForRow(at: indexPath)
            switch indexPath.row {
            case 0:
                presentChoices(title: "性别", values: SubjectSex.allCases, current: sex, source: source) {
                    [weak self] value in self?.sex = value
                }
            case 1:
                presentChoices(title: "惯用手", values: DominantHand.allCases, current: hand, source: source) {
                    [weak self] value in self?.hand = value
                }
            default:
                presentChoices(title: "分组", values: ResearchGroup.allCases, current: group, source: source) {
                    [weak self] value in self?.group = value
                }
            }
        case .notes:
            notesView.becomeFirstResponder()
        }
    }

    private func presentChoices<T: RawRepresentable & Equatable>(
        title: String,
        values: [T],
        current: T,
        source: UIView?,
        change: @escaping (T) -> Void
    ) where T.RawValue == String {
        let alert = UIAlertController(
            title: title,
            message: "当前：\(current.rawValue)",
            preferredStyle: .actionSheet
        )
        values.forEach { value in
            alert.addAction(UIAlertAction(title: value.rawValue, style: .default) { [weak self] _ in
                change(value)
                self?.tableView.reloadSections(IndexSet(integer: Section.demographics.rawValue), with: .none)
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

    private func save() {
        let age: Int?
        let ageText = ageField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ageText.isEmpty {
            age = nil
        } else if let parsed = Int(ageText) {
            age = parsed
        } else {
            presentError(BackendError.validation("年龄应为整数。"), title: "无法保存")
            return
        }
        do {
            try backend.saveSubject(
                id: subject?.id,
                input: SubjectFormInput(
                    code: codeField.text ?? "",
                    age: age,
                    sex: sex,
                    dominantHand: hand,
                    researchGroup: group,
                    notes: notesView.text
                )
            )
            onSaved?()
            dismiss(animated: true)
        } catch {
            presentError(error, title: "无法保存")
        }
    }
}

@MainActor
final class SubjectDetailViewController: UITableViewController {
    private let backend: any AppBackend
    private let subjectID: UUID
    private var subject: SubjectSnapshot?
    private var sessions: [SessionSnapshot] = []
    var onOpenSession: ((UUID) -> Void)?

    init(backend: any AppBackend, subjectID: UUID) {
        self.backend = backend
        self.subjectID = subjectID
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "编辑",
            image: UIImage(systemName: "pencil"),
            primaryAction: UIAction { [weak self] _ in self?.edit() }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 5 : sessions.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "受试者信息" : "历史测试"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let subject else { return UITableViewCell() }
        if indexPath.section == 0 {
            let values = [
                ("研究编号", subject.code),
                ("年龄", subject.age.map { "\($0) 岁" } ?? "未填写"),
                ("性别", subject.sex.rawValue),
                ("惯用手", subject.dominantHand.rawValue),
                ("分组", subject.researchGroup.rawValue)
            ]
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = values[indexPath.row].0
            cell.detailTextLabel?.text = values[indexPath.row].1
            cell.selectionStyle = .none
            return cell
        }
        let session = sessions[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = session.displayName
        cell.detailTextLabel?.text = "\(session.mode.rawValue) · \(session.state.title) · \(session.completedTaskCount)/\(session.taskCount)"
        cell.imageView?.image = UIImage(systemName: session.state == .completed ? "checkmark.seal" : "list.clipboard")
        cell.imageView?.tintColor = session.state == .completed ? .systemGreen : .systemTeal
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        onOpenSession?(sessions[indexPath.row].id)
    }

    private func reload() {
        do {
            subject = try backend.subject(id: subjectID)
            sessions = try backend.subjectSessions(subjectID: subjectID)
            title = subject?.code ?? "受试者"
            tableView.reloadData()
            contentUnavailableConfiguration = subject == nil
                ? UIKitFactory.emptyConfiguration(title: "受试者不可用", message: "记录已删除或无法读取。", symbol: "person.slash")
                : nil
        } catch {
            presentError(error)
        }
    }

    private func edit() {
        guard let subject else { return }
        let editor = SubjectEditorViewController(backend: backend, subject: subject)
        editor.onSaved = { [weak self] in self?.reload() }
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }
}
