import UIKit

@MainActor
final class TaskRunnerViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let runner: any TaskRunControlling
    private let definition: ResearchTaskDefinition
    private let templateView: TaskTemplateUIView
    private let pencilView = PencilCaptureUIView()
    private let tappingView = TappingCaptureUIView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let instructionLabel = UILabel()
    private let statusLabel = UILabel()
    private let metricsLabel = UILabel()
    private let actionStack = UIStackView()
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var interrupted = false
    var onFinished: (() -> Void)?

    init(runner: any TaskRunControlling) {
        self.runner = runner
        definition = runner.context.definition
        templateView = TaskTemplateUIView(definition: runner.context.definition)
        super.init(nibName: nil, bundle: nil)
        title = "任务 \(runner.context.taskNumber)/\(runner.context.totalTasks)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "task.runner"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "退出",
            primaryAction: UIAction { [weak self] _ in self?.requestClose() }
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "task.exit"
        configureHeader()
        configureCanvas()
        configureActions()
        configureBindings()
        render(runner.state)
        presentationController?.delegate = self

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.interruptCapture() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.interrupted else { return }
                self.interrupted = false
                self.presentInterruptionNotice()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        runner.updateCanvasSize(templateView.bounds.size)
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if case .saving = runner.state.phase { return false }
        return runner.state.phase == .ready || runner.state.phase == .completed
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        requestClose()
    }

    private func configureHeader() {
        instructionLabel.font = .preferredFont(forTextStyle: .title2)
        instructionLabel.adjustsFontForContentSizeCategory = true
        instructionLabel.textColor = .label
        instructionLabel.text = definition.instruction
        instructionLabel.numberOfLines = 0

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        metricsLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        metricsLabel.adjustsFontForContentSizeCategory = true
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.textAlignment = .right

        let statusRow = UIStackView(arrangedSubviews: [statusLabel, metricsLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.spacing = 16
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metricsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [instructionLabel, statusRow, progressView])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
        header.accessibilityIdentifier = "task.instructions"
    }

    private func configureCanvas() {
        templateView.backgroundColor = .secondarySystemBackground
        templateView.layer.cornerCurve = .continuous
        templateView.layer.cornerRadius = 18
        templateView.clipsToBounds = true
        templateView.translatesAutoresizingMaskIntoConstraints = false
        templateView.accessibilityIdentifier = "task.canvas"
        view.addSubview(templateView)

        pencilView.taskID = runner.context.taskID
        pencilView.translatesAutoresizingMaskIntoConstraints = false
        tappingView.taskID = runner.context.taskID
        tappingView.translatesAutoresizingMaskIntoConstraints = false
        templateView.addSubview(pencilView)
        templateView.addSubview(tappingView)

        NSLayoutConstraint.activate([
            templateView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            templateView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            templateView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            pencilView.leadingAnchor.constraint(equalTo: templateView.leadingAnchor),
            pencilView.trailingAnchor.constraint(equalTo: templateView.trailingAnchor),
            pencilView.topAnchor.constraint(equalTo: templateView.topAnchor),
            pencilView.bottomAnchor.constraint(equalTo: templateView.bottomAnchor),
            tappingView.leadingAnchor.constraint(equalTo: templateView.leadingAnchor),
            tappingView.trailingAnchor.constraint(equalTo: templateView.trailingAnchor),
            tappingView.topAnchor.constraint(equalTo: templateView.topAnchor),
            tappingView.bottomAnchor.constraint(equalTo: templateView.bottomAnchor)
        ])
        tappingView.isHidden = definition.interaction != .tapping
        pencilView.isHidden = definition.interaction == .tapping
    }

    private func configureActions() {
        actionStack.axis = .horizontal
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 12
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionStack)
        NSLayoutConstraint.activate([
            actionStack.topAnchor.constraint(equalTo: templateView.bottomAnchor, constant: 16),
            actionStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            actionStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    private func configureBindings() {
        pencilView.onSamples = { [weak self] values in self?.runner.receive(samples: values) }
        pencilView.onSampleUpdates = { [weak self] values in self?.runner.receive(updates: values) }
        pencilView.onPencilDetection = { [weak self] source in
            self?.runner.recordPencilDetection(source)
        }
        tappingView.onTap = { [weak self] value in self?.runner.receive(tap: value) }
        runner.onStateChange = { [weak self] state in self?.render(state) }
    }

    private func render(_ state: TaskRunViewState) {
        let isRecording = state.phase == .recording
        pencilView.isRecording = isRecording
        tappingView.isRecording = isRecording
        navigationItem.leftBarButtonItem?.isEnabled = !isSaving(state.phase)
        isModalInPresentation = isSaving(state.phase) || isRecording

        let countText = definition.interaction == .tapping
            ? "\(state.tapCount) 次点击"
            : "\(state.sampleCount) 个采集点"
        let remaining = state.overallRemainingTime ?? runner.context.overallDuration
        let overallText = remaining >= 0
            ? "整体剩余 \(remaining.neurotraceFormattedDuration)"
            : "已超预计 \((-remaining).neurotraceFormattedDuration)"
        metricsLabel.text = "\(overallText) · 本项 \(state.elapsed.neurotraceFormattedDuration) · \(countText)"
        if let overallRemaining = state.overallRemainingTime {
            let elapsed = runner.context.overallDuration - overallRemaining
            progressView.progress = Float(min(max(elapsed / runner.context.overallDuration, 0), 1))
        } else {
            progressView.progress = 0
        }
        progressView.isHidden = false

        switch state.phase {
        case .ready:
            statusLabel.text = definition.interaction == .tapping ? "准备好后开始敲击" : "准备好 Apple Pencil 后开始"
            statusLabel.textColor = .secondaryLabel
            setActions([button(title: "开始", symbol: "play.fill", prominent: true, identifier: "task.start") { [weak self] in
                self?.resetCaptureViews()
                Task { await self?.runner.start() }
            }])
        case .recording:
            statusLabel.text = state.pencilIsAway ? "请将笔尖放回目标区域" : "正在采集"
            statusLabel.textColor = state.pencilIsAway ? .systemOrange : .systemRed
            setActions([button(title: "结束采集", symbol: "stop.fill", prominent: true, identifier: "task.finish") { [weak self] in
                self?.runner.finish()
            }])
        case .review:
            statusLabel.text = "采集完成，请确认结果"
            statusLabel.textColor = .secondaryLabel
            setActions([
                button(title: "重做", symbol: "arrow.counterclockwise") { [weak self] in Task { await self?.runner.redo() } },
                button(title: "保存", symbol: "checkmark", prominent: true, identifier: "task.save") { [weak self] in Task { await self?.runner.save() } }
            ])
        case let .saving(message):
            statusLabel.text = message
            statusLabel.textColor = .secondaryLabel
            setActions([])
        case .completed:
            statusLabel.text = "任务已保存"
            statusLabel.textColor = .systemGreen
            setActions([button(title: "完成", symbol: "checkmark", prominent: true, identifier: "task.done") { [weak self] in
                self?.finishAndClose()
            }])
        case let .failed(message):
            statusLabel.text = message
            statusLabel.textColor = .systemRed
            setActions([
                button(title: "退出", symbol: "xmark") { [weak self] in self?.close() },
                button(title: "重试", symbol: "arrow.counterclockwise", prominent: true) { [weak self] in
                    self?.resetCaptureViews()
                    Task { await self?.runner.redo() }
                }
            ])
        }
    }

    private func button(
        title: String,
        symbol: String,
        prominent: Bool = false,
        identifier: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> UIButton {
        let button = UIKitFactory.glassButton(title: title, symbol: symbol, prominent: prominent, action: action)
        button.accessibilityIdentifier = identifier
        return button
    }

    private func setActions(_ buttons: [UIButton]) {
        actionStack.arrangedSubviews.forEach { view in actionStack.removeArrangedSubview(view); view.removeFromSuperview() }
        buttons.forEach(actionStack.addArrangedSubview)
    }

    private func resetCaptureViews() {
        pencilView.reset()
        tappingView.reset()
    }

    private func requestClose() {
        if isSaving(runner.state.phase) { return }
        if runner.state.phase == .recording {
            let alert = UIAlertController(
                title: "退出当前任务？",
                message: "本次未保存的采集将标记为需要重做。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "继续采集", style: .cancel))
            alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
                Task { @MainActor in await self?.runner.exit(); self?.close() }
            })
            present(alert, animated: true)
        } else {
            Task { @MainActor in await runner.exit(); close() }
        }
    }

    private func interruptCapture() {
        guard runner.state.phase == .recording else { return }
        interrupted = true
        Task { await runner.exit() }
    }

    private func presentInterruptionNotice() {
        let alert = UIAlertController(
            title: "采集已中断",
            message: "应用进入后台时已安全关闭恢复日志，请重做本任务。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func finishAndClose() {
        onFinished?()
        dismiss(animated: true)
    }

    private func close() {
        onFinished?()
        dismiss(animated: true)
    }

    private func isSaving(_ phase: TaskRunPhase) -> Bool {
        if case .saving = phase { return true }
        return false
    }

}

@MainActor
private final class TaskTemplateUIView: UIView {
    private let definition: ResearchTaskDefinition

    init(definition: ResearchTaskDefinition) {
        self.definition = definition
        super.init(frame: .zero)
        isOpaque = true
        accessibilityLabel = "\(definition.title)采集区域"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        UIColor.secondarySystemBackground.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.tertiaryLabel.cgColor)
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if definition.template == .sentence {
            let text = "Today is a sunny day."
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .largeTitle),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: max(24, (bounds.width - size.width) / 2), y: bounds.height * 0.28), withAttributes: attributes)
            context.setStrokeColor(UIColor.separator.cgColor)
            context.setLineWidth(2)
            context.move(to: CGPoint(x: bounds.width * 0.1, y: bounds.height * 0.68))
            context.addLine(to: CGPoint(x: bounds.width * 0.9, y: bounds.height * 0.68))
            context.strokePath()
            return
        }

        let points = TaskCatalog.referencePoints(for: definition.kind, in: bounds.size)
        if points.count == 1, let point = points.first {
            context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.35).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56))
            context.setFillColor(UIColor.systemTeal.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
            return
        }
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
}
