import UIKit

@MainActor
final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable { case model, connection, research, diagnostics }
    private let backend: any AppBackend
    private var settings: AppSettingsSnapshot

    init(backend: any AppBackend) {
        self.backend = backend
        settings = backend.settings()
        super.init(style: .insetGrouped)
        title = "设置"
        navigationItem.largeTitleDisplayMode = .always
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "screen.设置"
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .model: 4
        case .connection: 3
        case .research: 2
        case .diagnostics: 4
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .model: "大模型分析"
        case .connection: "连接"
        case .research: "研究说明"
        case .diagnostics: "诊断信息"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .model else { return nil }
        return "API Key 仅保存在系统 Keychain；端点、模型名和开关保存在本机设置中。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.section)!
        switch section {
        case .model:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = "启用大模型补充分析"
                configuration.secondaryText = "本地模型和特征计算不受影响"
                configuration.image = UIImage(systemName: "brain.head.profile")
                configuration.imageProperties.tintColor = .systemTeal
                cell.contentConfiguration = configuration
                let toggle = UISwitch()
                toggle.isOn = settings.largeModelEnabled
                toggle.accessibilityIdentifier = "settings.model.enabled"
                toggle.addAction(UIAction { [weak self, weak toggle] _ in
                    guard let self, let toggle else { return }
                    settings.largeModelEnabled = toggle.isOn
                    save()
                    tableView.reloadData()
                }, for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
                return cell
            }
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let values = [
                ("端点", shortEndpoint, "network"),
                ("模型", settings.model.isEmpty ? "未设置" : settings.model, "cube"),
                ("API Key", settings.apiKey.isEmpty ? "未设置" : "已安全保存", "key")
            ][indexPath.row - 1]
            cell.textLabel?.text = values.0
            cell.detailTextLabel?.text = values.1
            cell.imageView?.image = UIImage(systemName: values.2)
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        case .connection:
            let rows = [
                ("测试连接", "bolt.horizontal.circle"),
                ("获取模型列表", "list.bullet.rectangle"),
                ("恢复默认端点与模型", "arrow.counterclockwise")
            ]
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = rows[indexPath.row].0
            cell.imageView?.image = UIImage(systemName: rows[indexPath.row].1)
            cell.imageView?.tintColor = .systemTeal
            cell.accessoryType = .disclosureIndicator
            return cell
        case .research:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if indexPath.row == 0 {
                cell.textLabel?.text = "仅供科研"
                cell.detailTextLabel?.text = "分析结果不构成医疗诊断或治疗建议。"
                cell.imageView?.image = UIImage(systemName: "cross.case")
            } else {
                cell.textLabel?.text = "数据保存"
                cell.detailTextLabel?.text = "原始点、点击事件、特征和报告默认仅存于本机。"
                cell.imageView?.image = UIImage(systemName: "externaldrive")
            }
            cell.detailTextLabel?.numberOfLines = 0
            cell.selectionStyle = .none
            return cell
        case .diagnostics:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            let rows = [
                ("数据库", "ParchmentV2"),
                ("文件目录", "ParchmentDataV2"),
                ("导出协议", SessionAnalysisReport.schemaVersion),
                ("系统", "iPadOS \(UIDevice.current.systemVersion)")
            ]
            cell.textLabel?.text = rows[indexPath.row].0
            cell.detailTextLabel?.text = rows[indexPath.row].1
            cell.selectionStyle = .none
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .model:
            switch indexPath.row {
            case 1: editEndpoint()
            case 2: editModel()
            case 3: editAPIKey()
            default: break
            }
        case .connection:
            switch indexPath.row {
            case 0: testConnection()
            case 1: fetchModels()
            case 2: restoreDefaults()
            default: break
            }
        case .research, .diagnostics: break
        }
    }

    private var shortEndpoint: String {
        guard let url = URL(string: settings.endpoint), let host = url.host else {
            return settings.endpoint.isEmpty ? "未设置" : settings.endpoint
        }
        return host
    }

    private func editEndpoint() {
        presentTextPrompt(
            title: "API 端点",
            message: "支持 OpenAI-compatible 基础地址或 chat/completions 完整地址。",
            value: settings.endpoint,
            placeholder: LargeModelConfiguration.defaultEndpoint,
            keyboardType: .URL
        ) { [weak self] value in
            guard let self else { return }
            settings.endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
            save()
            tableView.reloadData()
        }
    }

    private func editModel() {
        presentTextPrompt(
            title: "模型名",
            value: settings.model,
            placeholder: LargeModelConfiguration.defaultModel
        ) { [weak self] value in
            guard let self else { return }
            settings.model = value.trimmingCharacters(in: .whitespacesAndNewlines)
            save()
            tableView.reloadData()
        }
    }

    private func editAPIKey() {
        presentTextPrompt(
            title: "API Key",
            message: "凭据会存入系统 Keychain。留空可清除。",
            value: settings.apiKey,
            placeholder: "sk-…",
            secure: true
        ) { [weak self] value in
            guard let self else { return }
            settings.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
            save()
            tableView.reloadData()
        }
    }

    private func testConnection() {
        guard settings.configurationIsReady else {
            showMessage(title: "配置不完整", message: "请启用大模型分析，并填写有效端点和模型名。")
            return
        }
        let activity = UIActivityIndicatorView(style: .medium)
        activity.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activity)
        Task { @MainActor in
            defer { navigationItem.rightBarButtonItem = nil }
            do {
                showMessage(title: "连接成功", message: try await backend.testLargeModel(settings: settings))
            } catch { presentError(error, title: "连接失败") }
        }
    }

    private func fetchModels() {
        guard settings.configurationIsReady else {
            showMessage(title: "配置不完整", message: "请先完成端点和模型配置。")
            return
        }
        Task { @MainActor in
            do {
                let models = try await backend.listModels(settings: settings)
                let picker = ModelPickerViewController(models: models, selected: settings.model)
                picker.onSelect = { [weak self] model in
                    guard let self else { return }
                    settings.model = model
                    save()
                    tableView.reloadData()
                }
                navigationController?.pushViewController(picker, animated: true)
            } catch { presentError(error, title: "无法获取模型") }
        }
    }

    private func restoreDefaults() {
        settings.endpoint = LargeModelConfiguration.defaultEndpoint
        settings.model = LargeModelConfiguration.defaultModel
        save()
        tableView.reloadData()
    }

    private func save() {
        do { try backend.saveSettings(settings) }
        catch { presentError(error, title: "无法保存设置") }
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

@MainActor
private final class ModelPickerViewController: UITableViewController, UISearchResultsUpdating {
    private let models: [String]
    private let selected: String
    private var query = ""
    var onSelect: ((String) -> Void)?

    init(models: [String], selected: String) {
        self.models = models
        self.selected = selected
        super.init(style: .insetGrouped)
        title = "选择模型"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜索模型"
        navigationItem.searchController = search
    }

    private var filtered: [String] {
        query.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let value = filtered[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = value
        cell.accessoryType = value == selected ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(filtered[indexPath.row])
        navigationController?.popViewController(animated: true)
    }
}
