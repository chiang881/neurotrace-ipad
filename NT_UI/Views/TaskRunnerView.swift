import SwiftData
import SwiftUI

struct TaskRunnerView: View {
    private enum RunnerPhase: Equatable {
        case ready
        case countdown(Int)
        case recording
        case review
        case saving
        case saved
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let session: TestSession
    let task: TaskRecord

    @State private var phase: RunnerPhase = .ready
    @State private var samples: [PencilSample] = []
    @State private var taps: [TapEvent] = []
    @State private var sampleIndexByID: [UUID: Int] = [:]
    @State private var resetToken = UUID()
    @State private var elapsed: TimeInterval = 0
    @State private var recordingStartTime: TimeInterval?
    @State private var writer: CaptureLogWriter?
    @State private var errorMessage: String?
    @State private var lastPencilTimestamp: TimeInterval?
    @State private var savingMessage = "正在保存原始数据并计算特征…"

    private var definition: ResearchTaskDefinition {
        TaskCatalog.definition(for: task.taskKind)
    }

    private var canFinish: Bool {
        switch definition.interaction {
        case .tapping: !taps.isEmpty
        case .drawing, .hold: samples.count > 1
        }
    }

    private var remainingTime: TimeInterval? {
        definition.fixedDuration.map { max(0, $0 - elapsed) }
    }

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            VStack(spacing: 16) {
                header
                captureSurface
                controls
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("\(task.orderIndex + 1) / \(session.tasks.count)")
        .accessibilityIdentifier("task.runner")
        .interactiveDismissDisabled(phase == .saving)
        .task(id: phase) {
            guard phase == .recording else { return }
            await runTimer()
        }
        .onDisappear {
            guard phase != .saved, task.state == .inProgress else { return }
            task.state = .needsRedo
            session.state = .inProgress
            session.updatedAt = .now
            try? modelContext.save()
            Task { try? await writer?.close() }
        }
        .alert("任务错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(definition.title + (definition.hand == .none ? "" : " · \(definition.hand.rawValue)"))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("task.runner")
                Text(definition.instruction)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer()
            if let remainingTime {
                metric(title: "剩余时间", value: "\(Int(ceil(remainingTime))) 秒")
            } else {
                metric(title: "用时", value: elapsed.formattedDuration)
            }
            metric(
                title: definition.interaction == .tapping ? "点击事件" : "采集点",
                value: "\(definition.interaction == .tapping ? taps.count : samples.count)"
            )
            if definition.interaction == .tapping {
                StatusPill(text: "手指触屏", color: .cyan)
            } else {
                StatusPill(
                    text: services.pencilMonitor.hasDetectedPencil ? "已检测 Pencil" : "未检测 Pencil",
                    color: services.pencilMonitor.hasDetectedPencil ? .mint : .orange
                )
            }
        }
        .padding(.top, 8)
    }

    private var captureSurface: some View {
        GeometryReader { proxy in
            ParchmentCanvasSurface {
                ZStack {
                    TaskTemplateOverlay(task: definition)

                    switch definition.interaction {
                    case .drawing, .hold:
                        PencilCanvasView(
                            taskID: task.id,
                            isRecording: phase == .recording,
                            resetToken: resetToken,
                            pencilMonitor: services.pencilMonitor,
                            onSamples: receive(samples:),
                            onSampleUpdates: receive(updates:)
                        )

                    case .tapping:
                        TappingPadView(
                            taskID: task.id,
                            isRecording: phase == .recording,
                            resetToken: resetToken,
                            onTap: receive(tap:)
                        )
                    }

                    overlay
                }
            }
            .onAppear {
                task.canvasWidth = proxy.size.width
                task.canvasHeight = proxy.size.height
            }
            .onChange(of: proxy.size) { _, size in
                task.canvasWidth = size.width
                task.canvasHeight = size.height
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch phase {
        case .ready:
            instructionOverlay(
                symbol: definition.interaction == .tapping ? "hand.tap.fill" : "pencil.tip",
                title: "准备好后开始",
                message: definition.interaction == .tapping
                    ? "任务开始后请按亮起顺序交替点击。"
                    : "Apple Pencil 状态只根据实际输入判断，不代表蓝牙连接状态。"
            )

        case .countdown(let value):
            ZStack {
                Color.black.opacity(0.24)
                Text("\(value)")
                    .font(.system(size: 112, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 16)
            }

        case .recording:
            if definition.interaction == .hold, pencilIsAway {
                VStack {
                    Text("检测到笔尖离开，请尽量保持接触")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(.white.opacity(0.88), in: .capsule)
                    Spacer()
                }
                .padding(.top, 18)
            }

        case .review:
            VStack {
                Spacer()
                HStack(spacing: 18) {
                    reviewMetric("用时", elapsed.formattedDuration)
                    reviewMetric("采集点", "\(samples.count)")
                    reviewMetric("点击", "\(taps.count)")
                    reviewMetric("笔画", "\(Set(samples.map(\.strokeID)).count)")
                }
                .padding(18)
                .background(.black.opacity(0.58), in: .rect(cornerRadius: 18))
                .padding()
            }

        case .saving:
            ZStack {
                Color.black.opacity(0.30)
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text(savingMessage)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }

        case .saved:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            switch phase {
            case .ready:
                Button {
                    Task { await start() }
                } label: {
                    Label(task.state == .needsRedo ? "重新开始" : "开始", systemImage: "play.fill")
                        .frame(width: 180, height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)

            case .countdown:
                Button("取消倒计时", role: .cancel) {
                    phase = .ready
                }
                .buttonStyle(.glass)

            case .recording:
                Button {
                    finishRecording()
                } label: {
                    Label("完成任务", systemImage: "stop.fill")
                        .frame(width: 180, height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .disabled(!canFinish || definition.fixedDuration != nil)

            case .review:
                Button {
                    Task { await redo() }
                } label: {
                    Label("重做", systemImage: "arrow.counterclockwise")
                        .frame(width: 150, height: 48)
                }
                .buttonStyle(.glass)

                Button {
                    Task { await save() }
                } label: {
                    Label("保存任务", systemImage: "checkmark.circle.fill")
                        .frame(width: 180, height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.mint)

            case .saving, .saved:
                EmptyView()
            }

            Spacer()
            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var statusMessage: String {
        switch phase {
        case .ready: "开始前会进行 3 秒倒计时"
        case .countdown: "请保持准备姿势"
        case .recording:
            definition.fixedDuration == nil ? "完成后点击“完成任务”" : "到时后自动结束"
        case .review: "确认预览后保存，或重做本项"
        case .saving: "请勿退出"
        case .saved: "已保存"
        }
    }

    private var pencilIsAway: Bool {
        guard phase == .recording, let lastPencilTimestamp else { return elapsed > 0.8 }
        return ProcessInfo.processInfo.systemUptime - lastPencilTimestamp > 0.35
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(minWidth: 92, alignment: .trailing)
    }

    private func reviewMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(minWidth: 82)
    }

    private func instructionOverlay(symbol: String, title: String, message: String) -> some View {
        ZStack {
            Color.black.opacity(0.16)
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ParchmentPalette.ink)
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(ParchmentPalette.ink)
                Text(message)
                    .foregroundStyle(ParchmentPalette.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .padding(26)
            .background(.white.opacity(0.78), in: .rect(cornerRadius: 22))
        }
    }

    private func start() async {
        samples.removeAll(keepingCapacity: true)
        taps.removeAll(keepingCapacity: true)
        sampleIndexByID.removeAll(keepingCapacity: true)
        elapsed = 0
        lastPencilTimestamp = nil
        resetToken = UUID()
        task.attemptCount += 1
        task.state = .inProgress
        task.startedAt = .now
        session.startedAt = session.startedAt ?? .now
        session.state = .inProgress
        session.updatedAt = .now
        try? modelContext.save()

        for value in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            phase = .countdown(value)
            try? await Task.sleep(for: .seconds(1))
            guard phase == .countdown(value) else { return }
        }

        do {
            writer = try await services.captureStore.beginRecoveryLog(
                sessionID: session.id,
                taskID: task.id,
                attempt: task.attemptCount
            )
            recordingStartTime = ProcessInfo.processInfo.systemUptime
            phase = .recording
        } catch {
            task.state = .needsRedo
            phase = .ready
            errorMessage = error.localizedDescription
        }
    }

    private func runTimer() async {
        while !Task.isCancelled, phase == .recording {
            if let recordingStartTime {
                elapsed = ProcessInfo.processInfo.systemUptime - recordingStartTime
            }
            if let fixedDuration = definition.fixedDuration, elapsed >= fixedDuration {
                finishRecording()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        if let recordingStartTime {
            elapsed = ProcessInfo.processInfo.systemUptime - recordingStartTime
        }
        guard canFinish else {
            let activeWriter = writer
            writer = nil
            recordingStartTime = nil
            task.state = .needsRedo
            session.updatedAt = .now
            try? modelContext.save()
            phase = .ready
            errorMessage = definition.interaction == .tapping
                ? "本次未记录到有效点击，请确认使用手指点击目标后重试。"
                : "本次未记录到足够的 Apple Pencil 数据，请确认笔尖接触画布后重试。"
            Task { try? await activeWriter?.close() }
            return
        }
        phase = .review
        let activeWriter = writer
        writer = nil
        Task { try? await activeWriter?.close() }
    }

    private func receive(samples newSamples: [PencilSample]) {
        guard phase == .recording else { return }
        samples.append(contentsOf: newSamples)
        for (offset, sample) in newSamples.enumerated() {
            sampleIndexByID[sample.id] = samples.count - newSamples.count + offset
        }
        lastPencilTimestamp = newSamples.last?.timestamp
        let activeWriter = writer
        Task { try? await activeWriter?.append(samples: newSamples) }
    }

    private func receive(updates: [PencilSample]) {
        for update in updates {
            if let index = sampleIndexByID[update.id], samples.indices.contains(index) {
                samples[index] = update
            }
        }
    }

    private func receive(tap: TapEvent) {
        guard phase == .recording else { return }
        taps.append(tap)
        let activeWriter = writer
        Task { try? await activeWriter?.append(tap: tap) }
    }

    private func redo() async {
        try? await writer?.close()
        writer = nil
        samples.removeAll(keepingCapacity: true)
        taps.removeAll(keepingCapacity: true)
        sampleIndexByID.removeAll(keepingCapacity: true)
        elapsed = 0
        recordingStartTime = nil
        resetToken = UUID()
        task.state = .needsRedo
        session.updatedAt = .now
        try? modelContext.save()
        phase = .ready
    }

    private func save() async {
        guard phase == .review else { return }
        phase = .saving
        savingMessage = "正在保存原始数据并计算特征…"

        do {
            try await writer?.close()
            let commit = try await services.captureStore.commit(
                sessionID: session.id,
                taskID: task.id,
                attempt: task.attemptCount,
                samples: samples,
                taps: taps
            )
            let features = await services.featureEngine.compute(
                task: definition,
                samples: samples,
                taps: taps
            )

            task.samplesRelativePath = commit.samplesRelativePath
            task.tapsRelativePath = commit.tapsRelativePath
            task.recoveryRelativePath = commit.recoveryRelativePath
            task.features = features
            task.qualityFlags = features.qualityFlags
            task.sampleCount = samples.count
            task.tapCount = taps.count
            task.duration = elapsed
            task.completedAt = .now
            task.state = .completed

            if !samples.isEmpty {
                let canvasSize = CGSize(
                    width: max(1, task.canvasWidth),
                    height: max(1, task.canvasHeight)
                )
                let image = PreviewRenderer.render(task: definition, samples: samples, size: canvasSize)
                task.previewRelativePath = try PreviewRenderer.save(
                    image: image,
                    sessionID: session.id,
                    taskID: task.id,
                    attempt: task.attemptCount
                )
            }

            session.updatedAt = .now
            let didCompleteSession = session.tasks.allSatisfy { $0.state == .completed }
            if didCompleteSession {
                session.state = .completed
                session.completedAt = .now
            } else {
                session.state = .inProgress
            }
            try modelContext.save()

            if didCompleteSession {
                savingMessage = "任务已保存，分析报告将在后台生成…"
                services.scheduleAnalysis(session: session, context: modelContext, force: true)
            }

            phase = .saved
            dismiss()
        } catch {
            task.state = .needsRedo
            try? modelContext.save()
            phase = .review
            errorMessage = error.localizedDescription
        }
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let total = max(0, Int(self))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
