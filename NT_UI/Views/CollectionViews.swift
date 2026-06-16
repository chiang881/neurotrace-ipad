import SwiftData
import SwiftUI

struct CollectionRootView: View {
    @Query(sort: \Subject.updatedAt, order: .reverse) private var subjects: [Subject]
    @Query(sort: \TestSession.updatedAt, order: .reverse) private var sessions: [TestSession]
    @State private var showNewSession = false

    private var activeSessions: [TestSession] {
        sessions.filter { $0.state == .ready || $0.state == .inProgress }
    }

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        ScreenTitle(title: "数据采集", subtitle: "固定任务协议 · 自动保存 · 可中断续测")
                        Spacer()
                        Button {
                            showNewSession = true
                        } label: {
                            Label("新建测试", systemImage: "plus")
                                .font(.headline)
                                .frame(width: 160, height: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                        .disabled(subjects.isEmpty)
                    }

                    if subjects.isEmpty {
                        EmptyStateView(
                            symbol: "person.crop.circle.badge.exclamationmark",
                            title: "请先建立受试者",
                            message: "受试者编号是每份原始数据与导出文件的必要字段。"
                        )
                        NavigationLink {
                            SubjectsView()
                        } label: {
                            Label("前往受试者管理", systemImage: "person.crop.circle.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.cyan)
                    } else if activeSessions.isEmpty {
                        EmptyStateView(
                            symbol: "pencil.and.scribble",
                            title: "没有进行中的测试",
                            message: "点击“新建测试”选择受试者和测试模式。"
                        )
                    } else {
                        SectionTitle("进行中的测试")
                        ForEach(activeSessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("continue.session.row")
                        }
                    }

                    SectionTitle("采集协议")
                    protocolCard
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showNewSession) {
            NewSessionView()
        }
    }

    private var protocolCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("快速模式：静态/动态螺旋、静止保持、触屏敲击，共 6 项", systemImage: "hare.fill")
                Label("完整模式：全部 11 项任务", systemImage: "list.number")
                Label("任务固定顺序，不允许跳过；可重做或中断续测", systemImage: "arrow.clockwise")
                Label("绘图只采集 Apple Pencil；模拟器输入会写入质量标记", systemImage: "pencil.tip")
            }
            .foregroundStyle(.white.opacity(0.78))
        }
    }
}

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \Subject.updatedAt, order: .reverse) private var subjects: [Subject]

    @State private var selectedSubjectID: UUID?
    @State private var mode: TestMode = .full
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("受试者") {
                    Picker("研究编号", selection: $selectedSubjectID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(subjects) { subject in
                            Text(subject.code).tag(Optional(subject.id))
                        }
                    }
                }

                Section("测试模式") {
                    ForEach(TestMode.allCases) { option in
                        Button {
                            mode = option
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.rawValue)
                                        .font(.headline)
                                    Text(option == .quick ? "静态/动态螺旋、静止保持、触屏敲击" : "完整 11 项研究任务")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(option.estimatedDuration)
                                    Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(mode == option ? .blue : .secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("本次测试") {
                    LabeledContent("任务数量", value: "\(TaskCatalog.tasks(for: mode).count)")
                    LabeledContent("创建时间", value: Date.now.formatted(date: .numeric, time: .shortened))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建测试")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .fontWeight(.semibold)
                        .disabled(selectedSubjectID == nil)
                }
            }
            .onAppear {
                selectedSubjectID = selectedSubjectID ?? subjects.first?.id
            }
        }
    }

    private func create() {
        guard let subject = subjects.first(where: { $0.id == selectedSubjectID }) else {
            errorMessage = "请选择受试者。"
            return
        }
        do {
            _ = try services.createSession(subject: subject, mode: mode, context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SessionRow: View {
    let session: TestSession

    var body: some View {
        HStack(spacing: 18) {
            GlassIcon(
                symbol: session.state == .completed ? "checkmark.seal.fill" : "list.clipboard.fill",
                tint: session.state == .completed ? .mint : .cyan
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(session.subject?.code ?? "未知受试者")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("\(session.mode.rawValue) · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.white.opacity(0.62))
                ProgressView(value: session.progress)
                    .tint(session.state == .completed ? .mint : .cyan)
                    .frame(maxWidth: 420)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(
                    text: session.state.title,
                    color: session.state == .completed ? .mint : session.state == .abandoned ? .red : .cyan
                )
                Text("\(session.completedTaskCount) / \(session.tasks.count)")
                    .foregroundStyle(.white.opacity(0.58))
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(20)
        .parchmentGlass(cornerRadius: 24, tint: .white.opacity(0.05), interactive: true)
    }
}

struct SessionDetailView: View {
    private enum Route: Hashable, Identifiable {
        case runTask(UUID)
        case reviewTask(UUID)

        var id: String {
            switch self {
            case .runTask(let id): "run-\(id.uuidString)"
            case .reviewTask(let id): "review-\(id.uuidString)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    let session: TestSession

    @State private var showAbandonConfirmation = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var presentedRoute: Route?

    private var analysisProgress: AnalysisProgressState? {
        services.analysisProgress(for: session)
    }

    private var analysisIsRunning: Bool {
        isAnalyzing || analysisProgress != nil
    }

    private var resumableTask: TaskRecord? {
        guard session.state != .completed, session.state != .abandoned else { return nil }
        return session.nextTask
    }

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let task = resumableTask {
                        continueCurrentTaskCard(task)
                    }
                    analysisSection
                    ForEach(session.orderedTasks) { task in
                        taskRow(task)
                    }
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(session.subject?.code ?? "测试")
        .accessibilityIdentifier("session.detail")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $presentedRoute) { route in
            NavigationStack {
                destination(for: route)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                presentedRoute = nil
                            }
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.state == .completed {
                    Button(analysisIsRunning ? "评估中" : "重新评估", systemImage: "arrow.clockwise.circle") {
                        Task { await analyze(force: true) }
                    }
                    .disabled(analysisIsRunning)

                    Button("导出", systemImage: "square.and.arrow.up") {
                        Task { await export() }
                    }
                    .disabled(isExporting)
                } else if session.state != .abandoned {
                    Button("放弃测试", systemImage: "xmark.circle", role: .destructive) {
                        showAbandonConfirmation = true
                    }
                }
            }
        }
        .onAppear { refreshSessionState() }
        .sheet(item: Binding(
            get: { exportURL.map(ShareItem.init) },
            set: { exportURL = $0?.url }
        )) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert("确认放弃测试？", isPresented: $showAbandonConfirmation) {
            Button("取消", role: .cancel) {}
            Button("放弃", role: .destructive) { abandon() }
        } message: {
            Text("已完成的任务会保留，但测试无法继续。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        if session.state == .completed {
            if let analysisProgress {
                analysisProgressCard(analysisProgress)
            }

            if let report = session.analysisReport {
                AnalysisReportSummaryView(report: report)
                reevaluateCard
            } else {
                GlassCard(tint: .purple.opacity(0.08)) {
                    HStack(spacing: 16) {
                        GlassIcon(symbol: "doc.text.magnifyingglass", tint: .purple)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("尚未生成分析报告")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("测试结束后会自动在后台生成；也可手动调用本地模型和大模型 overall 重新汇总。")
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        Button {
                            Task { await analyze(force: true) }
                        } label: {
                            if analysisIsRunning {
                                ProgressView()
                                    .frame(width: 120, height: 46)
                            } else {
                                Label("开始评估", systemImage: "play.circle")
                                    .frame(width: 150, height: 46)
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.purple)
                        .disabled(analysisIsRunning)
                    }
                }
            }
        }
    }

    private func analysisProgressCard(_ progress: AnalysisProgressState) -> some View {
        GlassCard(tint: .purple.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    GlassIcon(symbol: "chart.bar.doc.horizontal", tint: .purple)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("正在评估")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(progress.message)
                            .foregroundStyle(.white.opacity(0.64))
                    }
                    Spacer()
                    Text("\(progress.completedUnits) / \(progress.totalUnits)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                }
                ProgressView(value: progress.fraction)
                    .tint(.purple)
            }
        }
    }

    private var reevaluateCard: some View {
        GlassCard(tint: .white.opacity(0.04)) {
            HStack(spacing: 14) {
                GlassIcon(symbol: "arrow.clockwise.circle", tint: .cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("已完成评估")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("需要重新调用本地模型和大模型 overall 时，可重新评估本次测试。")
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button {
                    Task { await analyze(force: true) }
                } label: {
                    if analysisIsRunning {
                        ProgressView()
                            .frame(width: 130, height: 44)
                    } else {
                        Label("重新评估", systemImage: "arrow.clockwise")
                            .frame(width: 150, height: 44)
                    }
                }
                .buttonStyle(.glass)
                .disabled(analysisIsRunning)
            }
        }
    }

    private var header: some View {
        GlassCard(tint: .cyan.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ScreenTitle(
                        title: session.subject?.code ?? "未知受试者",
                        subtitle: "\(session.mode.rawValue) · \(session.createdAt.formatted(date: .complete, time: .shortened))"
                    )
                    Spacer()
                    StatusPill(
                        text: session.state.title,
                        color: session.state == .completed ? .mint : session.state == .abandoned ? .red : .cyan
                    )
                }
                ProgressView(value: session.progress)
                    .tint(.cyan)
                Text("\(session.completedTaskCount) / \(session.tasks.count) 项已完成")
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
    }

    private func continueCurrentTaskCard(_ task: TaskRecord) -> some View {
        let definition = TaskCatalog.definition(for: task.taskKind)
        return GlassCard(tint: .cyan.opacity(0.06)) {
            HStack(spacing: 16) {
                GlassIcon(symbol: "play.circle.fill", tint: .cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("继续当前任务")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(task.orderIndex + 1). \(definition.title)\(definition.hand == .none ? "" : " · \(definition.hand.rawValue)")")
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button {
                    presentedRoute = .runTask(task.id)
                } label: {
                    Label(task.state == .needsRedo ? "重新开始" : "继续采集", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(width: 170, height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(.cyan)
                .accessibilityIdentifier("continue.current-task")
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TaskRecord) -> some View {
        let definition = TaskCatalog.definition(for: task.taskKind)
        let isCurrent = session.nextTask?.id == task.id

        if isCurrent && session.state != .completed && session.state != .abandoned {
            Button {
                presentedRoute = .runTask(task.id)
            } label: {
                taskRowLabel(task, definition: definition, isCurrent: true)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                presentedRoute = .runTask(task.id)
            })
        } else if task.state == .completed {
            Button {
                presentedRoute = .reviewTask(task.id)
            } label: {
                taskRowLabel(task, definition: definition, isCurrent: false)
            }
            .buttonStyle(.plain)
        } else {
            taskRowLabel(task, definition: definition, isCurrent: false)
                .opacity(0.68)
        }
    }

    private func taskRowLabel(
        _ task: TaskRecord,
        definition: ResearchTaskDefinition,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 16) {
            Text("\(task.orderIndex + 1)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(isCurrent ? Color.cyan.opacity(0.32) : Color.white.opacity(0.10), in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                Text(definition.title + (definition.hand == .none ? "" : " · \(definition.hand.rawValue)"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(task.state == .completed ? "\(task.sampleCount + task.tapCount) 个数据点 · \(String(format: "%.1f", task.duration)) 秒" : definition.instruction)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
            }
            Spacer()
            StatusPill(
                text: isCurrent && task.state == .pending ? "下一项" : task.state.title,
                color: task.state == .completed ? .mint : task.state == .needsRedo ? .orange : isCurrent ? .cyan : .gray
            )
            if isCurrent || task.state == .completed {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(18)
        .parchmentGlass(
            cornerRadius: 22,
            tint: (isCurrent ? Color.cyan : task.state == .completed ? .mint : .white).opacity(0.055),
            interactive: isCurrent || task.state == .completed
        )
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .runTask(let taskID):
            if let task = session.tasks.first(where: { $0.id == taskID }) {
                TaskRunnerView(session: session, task: task)
            } else {
                missingTaskView
            }

        case .reviewTask(let taskID):
            if let task = session.tasks.first(where: { $0.id == taskID }) {
                TaskRecordDetailView(task: task)
            } else {
                missingTaskView
            }
        }
    }

    private var missingTaskView: some View {
        ContentUnavailableView(
            "任务不可用",
            systemImage: "exclamationmark.triangle",
            description: Text("任务记录已被删除或无法读取，请返回会话列表。")
        )
    }

    private func refreshSessionState() {
        guard session.state != .abandoned else { return }

        var didChange = false
        if !session.tasks.isEmpty, session.tasks.allSatisfy({ $0.state == .completed }) {
            if session.state != .completed {
                session.state = .completed
                didChange = true
            }
            if session.completedAt == nil {
                session.completedAt = .now
                didChange = true
            }
        } else if
            session.tasks.contains(where: { $0.state != .pending }),
            session.state != .inProgress
        {
            session.state = .inProgress
            didChange = true
        }

        guard didChange else { return }
        session.updatedAt = .now
        try? modelContext.save()
    }

    private func abandon() {
        if let active = session.tasks.first(where: { $0.state == .inProgress }) {
            active.state = .needsRedo
        }
        session.state = .abandoned
        session.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            exportURL = try await services.exportService.export(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyze(force: Bool) async {
        guard !analysisIsRunning else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            try await services.analyze(session: session, context: modelContext, force: force)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TaskRecordDetailView: View {
    @Environment(AppServices.self) private var services
    let task: TaskRecord
    @State private var previewURL: URL?

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let definition = TaskCatalog.definition(for: task.taskKind)
                    ScreenTitle(
                        title: definition.title,
                        subtitle: definition.hand == .none ? "任务结果" : "\(definition.hand.rawValue) · 任务结果"
                    )

                    if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
                        ParchmentCanvasSurface {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("采集点", value: "\(task.sampleCount)")
                            LabeledContent("点击事件", value: "\(task.tapCount)")
                            LabeledContent("任务时长", value: "\(String(format: "%.2f", task.duration)) 秒")
                            LabeledContent("尝试次数", value: "\(task.attemptCount)")
                        }
                        .foregroundStyle(.white)
                    }

                    if let features = task.features {
                        SectionTitle("特征数据")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                            ForEach(features.values.keys.sorted(), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(key)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.56))
                                    Text(features.values[key] ?? 0, format: .number.precision(.fractionLength(4)))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.white)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .parchmentGlass(cornerRadius: 18, tint: .white.opacity(0.04), interactive: false)
                            }
                        }
                    }
                }
                .appScreenPadding()
            }
        }
        .task {
            previewURL = await services.captureStore.absoluteURL(relativePath: task.previewRelativePath)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
