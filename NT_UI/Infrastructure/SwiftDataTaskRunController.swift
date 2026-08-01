import CoreGraphics
import Foundation
import SwiftData

@MainActor
final class TaskRunStateMachine: TaskRunControlling {
    let context: TaskRunContext
    private(set) var state: TaskRunViewState {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((TaskRunViewState) -> Void)?

    private let session: TestSession
    private let task: TaskRecord
    private let modelContext: ModelContext
    private let services: AppServices
    private let definition: ResearchTaskDefinition

    private var samples: [PencilSample] = []
    private var taps: [TapEvent] = []
    private var sampleIndexByID: [UUID: Int] = [:]
    private var writer: CaptureLogWriter?
    private var timerTask: Task<Void, Never>?
    private var recordingStartTime: TimeInterval?
    private var lastPencilTimestamp: TimeInterval?

    init(
        session: TestSession,
        task: TaskRecord,
        context: ModelContext,
        services: AppServices
    ) {
        self.session = session
        self.task = task
        modelContext = context
        self.services = services
        definition = TaskCatalog.definition(for: task.taskKind)
        self.context = TaskRunContext(
            sessionID: session.id,
            taskID: task.id,
            taskNumber: task.orderIndex + 1,
            totalTasks: session.tasks.count,
            overallDuration: session.mode.overallDuration,
            definition: definition
        )
        state = TaskRunViewState(
            phase: .ready,
            elapsed: 0,
            sampleCount: 0,
            tapCount: 0,
            strokeCount: 0,
            overallRemainingTime: session.startedAt.map {
                session.mode.overallDuration - Date.now.timeIntervalSince($0)
            },
            pencilIsAway: false
        )
        if session.startedAt != nil {
            startTimer()
        }
    }

    deinit {
        timerTask?.cancel()
    }

    func start() async {
        guard state.phase == .ready || isFailure(state.phase) else { return }
        timerTask?.cancel()
        samples.removeAll(keepingCapacity: true)
        taps.removeAll(keepingCapacity: true)
        sampleIndexByID.removeAll(keepingCapacity: true)
        lastPencilTimestamp = nil
        task.attemptCount += 1
        task.state = .inProgress
        task.startedAt = .now
        session.startedAt = session.startedAt ?? .now
        session.state = .inProgress
        session.updatedAt = .now
        try? modelContext.save()

        do {
            writer = try await services.captureStore.beginRecoveryLog(
                sessionID: session.id,
                taskID: task.id,
                attempt: task.attemptCount
            )
            recordingStartTime = ProcessInfo.processInfo.systemUptime
            update(phase: .recording, elapsed: 0)
            startTimer()
        } catch {
            task.state = .needsRedo
            try? modelContext.save()
            update(phase: .failed(error.localizedDescription), elapsed: 0)
        }
    }

    func receive(samples newSamples: [PencilSample]) {
        guard state.phase == .recording, !newSamples.isEmpty else { return }
        let startIndex = samples.count
        samples.append(contentsOf: newSamples)
        for (offset, sample) in newSamples.enumerated() {
            sampleIndexByID[sample.id] = startIndex + offset
        }
        lastPencilTimestamp = newSamples.last?.timestamp
        let activeWriter = writer
        Task { try? await activeWriter?.append(samples: newSamples) }
        publishCounts()
    }

    func receive(updates: [PencilSample]) {
        for update in updates {
            if let index = sampleIndexByID[update.id], samples.indices.contains(index) {
                samples[index] = update
            }
        }
    }

    func receive(tap: TapEvent) {
        guard state.phase == .recording else { return }
        taps.append(tap)
        let activeWriter = writer
        Task { try? await activeWriter?.append(tap: tap) }
        publishCounts()
    }

    func recordPencilDetection(_ source: PencilMonitor.DetectionSource) {
        services.pencilMonitor.record(source)
    }

    func finish() {
        guard state.phase == .recording else { return }
        updateElapsed()
        guard hasEnoughInput else {
            let activeWriter = writer
            writer = nil
            recordingStartTime = nil
            task.state = .needsRedo
            session.updatedAt = .now
            try? modelContext.save()
            Task { try? await activeWriter?.close() }
            let message = definition.interaction == .tapping
                ? "未记录到有效点击，请使用手指点击目标后重试。"
                : "未记录到足够的 Apple Pencil 数据，请确认笔尖接触画布后重试。"
            update(phase: .failed(message), elapsed: state.elapsed)
            return
        }
        recordingStartTime = nil
        let activeWriter = writer
        writer = nil
        Task { try? await activeWriter?.close() }
        update(phase: .review, elapsed: state.elapsed)
    }

    func redo() async {
        try? await writer?.close()
        writer = nil
        samples.removeAll(keepingCapacity: true)
        taps.removeAll(keepingCapacity: true)
        sampleIndexByID.removeAll(keepingCapacity: true)
        recordingStartTime = nil
        lastPencilTimestamp = nil
        task.state = .needsRedo
        session.updatedAt = .now
        try? modelContext.save()
        state = TaskRunViewState(
            phase: .ready,
            elapsed: 0,
            sampleCount: 0,
            tapCount: 0,
            strokeCount: 0,
            overallRemainingTime: session.startedAt.map {
                session.mode.overallDuration - Date.now.timeIntervalSince($0)
            },
            pencilIsAway: false
        )
        startTimer()
    }

    func save() async {
        guard state.phase == .review else { return }
        update(phase: .saving("正在保存原始数据并计算特征…"), elapsed: state.elapsed)
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
            task.duration = state.elapsed
            task.completedAt = .now
            task.state = .completed

            if !samples.isEmpty {
                let size = CGSize(width: max(1, task.canvasWidth), height: max(1, task.canvasHeight))
                let image = PreviewRenderer.render(task: definition, samples: samples, size: size)
                task.previewRelativePath = try PreviewRenderer.save(
                    image: image,
                    sessionID: session.id,
                    taskID: task.id,
                    attempt: task.attemptCount
                )
            }

            session.updatedAt = .now
            let completed = session.tasks.allSatisfy { $0.state == .completed }
            session.state = completed ? .completed : .inProgress
            if completed { session.completedAt = .now }
            try modelContext.save()
            if completed {
                services.scheduleAnalysis(session: session, context: modelContext, force: true)
            }
            timerTask?.cancel()
            update(phase: .completed, elapsed: state.elapsed)
        } catch {
            task.state = .needsRedo
            try? modelContext.save()
            update(phase: .failed(error.localizedDescription), elapsed: state.elapsed)
        }
    }

    func exit() async {
        timerTask?.cancel()
        try? await writer?.close()
        writer = nil
        guard state.phase != .completed, task.state == .inProgress else { return }
        task.state = .needsRedo
        session.state = .inProgress
        session.updatedAt = .now
        try? modelContext.save()
        update(phase: .failed("采集已中断，本次任务需要重做。"), elapsed: state.elapsed)
    }

    func updateCanvasSize(_ size: CGSize) {
        task.canvasWidth = size.width
        task.canvasHeight = size.height
    }

    private var hasEnoughInput: Bool {
        definition.interaction == .tapping ? !taps.isEmpty : samples.count > 1
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state.phase != .completed else { return }
                if self.state.phase == .recording {
                    self.updateElapsed()
                    if let duration = self.definition.fixedDuration, self.state.elapsed >= duration {
                        self.finish()
                    }
                } else {
                    self.update(phase: self.state.phase, elapsed: self.state.elapsed)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func updateElapsed() {
        guard let recordingStartTime else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - recordingStartTime
        update(phase: state.phase, elapsed: elapsed)
    }

    private func publishCounts() {
        update(phase: state.phase, elapsed: state.elapsed)
    }

    private func update(phase: TaskRunPhase, elapsed: TimeInterval) {
        let overallRemaining = session.startedAt.map {
            session.mode.overallDuration - Date.now.timeIntervalSince($0)
        }
        let pencilAway: Bool
        if definition.interaction == .hold, phase == .recording {
            if let lastPencilTimestamp {
                pencilAway = ProcessInfo.processInfo.systemUptime - lastPencilTimestamp > 0.35
            } else {
                pencilAway = elapsed > 0.8
            }
        } else {
            pencilAway = false
        }
        state = TaskRunViewState(
            phase: phase,
            elapsed: elapsed,
            sampleCount: samples.count,
            tapCount: taps.count,
            strokeCount: Set(samples.map(\.strokeID)).count,
            overallRemainingTime: overallRemaining,
            pencilIsAway: pencilAway
        )
    }

    private func isFailure(_ phase: TaskRunPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}
