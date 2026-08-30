import Foundation
import Observation
import OSLog
import SwiftData
import UIKit

@MainActor
@Observable
final class PencilMonitor {
    enum DetectionSource: String {
        case contact = "笔尖接触"
        case hover = "悬停"
        case doubleTap = "双击"
        case squeeze = "挤压"
    }

    private(set) var lastDetectedAt: Date?
    private(set) var source: DetectionSource?

    var hasDetectedPencil: Bool { lastDetectedAt != nil }

    var statusText: String {
        guard let lastDetectedAt, let source else {
            return "等待 Apple Pencil 悬停、触碰或按键事件"
        }
        return "已通过\(source.rawValue)验证 · \(lastDetectedAt.formatted(date: .omitted, time: .shortened))"
    }

    func record(_ source: DetectionSource) {
        let shouldNotify = self.source != source || lastDetectedAt.map {
            Date.now.timeIntervalSince($0) > 1
        } ?? true
        lastDetectedAt = .now
        self.source = source
        if shouldNotify {
            NotificationCenter.default.post(name: .pencilMonitorDidChange, object: self)
        }
    }
}

extension Notification.Name {
    static let pencilMonitorDidChange = Notification.Name("neurotrace.PencilMonitorDidChange")
}

nonisolated protocol ResearchSyncClient: Sendable {
    func upload(manifest: ExportManifest, archiveURL: URL) async throws
}

nonisolated struct DisabledResearchSyncClient: ResearchSyncClient {
    func upload(manifest: ExportManifest, archiveURL: URL) async throws {
        throw SyncError.disabled
    }

    enum SyncError: LocalizedError {
        case disabled

        var errorDescription: String? {
            "当前版本未配置研究服务器。"
        }
    }
}

@MainActor
@Observable
final class AppServices {
    private static let logger = Logger(subsystem: "top.hadal.neurotrace", category: "SessionAnalysis")

    let captureStore: any CaptureStore
    let featureEngine: any FeatureComputing
    let exportService: SessionExporting
    let analysisService: SessionAnalysisService
    let syncClient: any ResearchSyncClient
    let pencilMonitor: PencilMonitor
    private(set) var analysisProgressBySessionID: [UUID: AnalysisProgressState] = [:]
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    init(
        captureStore: any CaptureStore = LocalCaptureStore(),
        featureEngine: any FeatureComputing = FeatureEngine(),
        syncClient: any ResearchSyncClient = DisabledResearchSyncClient()
    ) {
        self.captureStore = captureStore
        self.featureEngine = featureEngine
        self.syncClient = syncClient
        pencilMonitor = PencilMonitor()
        exportService = LocalSessionExporter(captureStore: captureStore)
        analysisService = SessionAnalysisService(captureStore: captureStore)
    }

    func createSession(subject: Subject, mode: TestMode, context: ModelContext) throws -> TestSession {
        let session = TestSession(
            subject: subject,
            mode: mode,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
        context.insert(session)
        for (index, definition) in TaskCatalog.tasks(
            for: mode,
            dominantHand: subject.dominantHand
        ).enumerated() {
            let record = TaskRecord(taskKind: definition.kind, orderIndex: index)
            record.session = session
            session.tasks.append(record)
            context.insert(record)
        }
        subject.updatedAt = .now
        try context.save()
        return session
    }

    func recoverInterruptedTasks(context: ModelContext) throws {
        let descriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.stateRawValue == "inProgress" }
        )
        for task in try context.fetch(descriptor) {
            task.state = .needsRedo
            task.session?.state = .inProgress
            task.session?.updatedAt = .now
        }
        try context.save()
    }

    func delete(session: TestSession, context: ModelContext) async throws {
        let id = session.id
        context.delete(session)
        try context.save()
        try await captureStore.removeSession(id)
    }

    @discardableResult
    func analyze(
        session: TestSession,
        context: ModelContext,
        force: Bool = false
    ) async throws -> SessionAnalysisReport {
        if !force, let report = session.analysisReport {
            return report
        }
        let sessionID = session.id
        analysisProgressBySessionID[sessionID] = AnalysisProgressState(
            completedUnits: 0,
            totalUnits: 1,
            message: "正在准备评估..."
        )
        defer { analysisProgressBySessionID[sessionID] = nil }

        let report = await analysisService.analyze(session: session) { [weak self] progress in
            self?.analysisProgressBySessionID[sessionID] = progress
        }
        session.analysisReport = report
        session.updatedAt = .now
        try context.save()
        return report
    }

    func analysisProgress(for session: TestSession) -> AnalysisProgressState? {
        analysisProgressBySessionID[session.id]
    }

    func scheduleAnalysis(
        session: TestSession,
        context: ModelContext,
        force: Bool = false
    ) {
        let sessionID = session.id
        analysisTasks[sessionID]?.cancel()
        analysisTasks[sessionID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.analysisTasks[sessionID] = nil }
            do {
                try await self.analyze(session: session, context: context, force: force)
            } catch {
                Self.logger.error("后台报告生成失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
