import CoreGraphics
import Foundation

nonisolated struct SubjectSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let code: String
    let age: Int?
    let sex: SubjectSex
    let dominantHand: DominantHand
    let researchGroup: ResearchGroup
    let notes: String
    let sessionCount: Int
    let updatedAt: Date
}

nonisolated struct SubjectFormInput: Sendable {
    var code: String
    var age: Int?
    var sex: SubjectSex
    var dominantHand: DominantHand
    var researchGroup: ResearchGroup
    var notes: String
}

nonisolated struct SessionSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let subjectID: UUID?
    let subjectCode: String
    let displayName: String
    let hasCustomName: Bool
    let mode: TestMode
    let state: SessionState
    let createdAt: Date
    let startedAt: Date?
    let updatedAt: Date
    let completedAt: Date?
    let completedTaskCount: Int
    let taskCount: Int
    let hasAnalysisReport: Bool

    var progress: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount)
    }

    func overallRemainingTime(at date: Date = .now) -> TimeInterval? {
        guard let startedAt else { return nil }
        return mode.overallDuration - date.timeIntervalSince(startedAt)
    }
}

nonisolated struct TaskSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let orderIndex: Int
    let kind: ResearchTaskKind
    let title: String
    let instruction: String
    let hand: TestHand
    let state: TaskState
    let sampleCount: Int
    let tapCount: Int
    let duration: TimeInterval
    let attemptCount: Int
    let featureValues: [String: Double]
    let qualityFlags: [String]
    let hasPreview: Bool
}

nonisolated struct SessionDetailSnapshot: Sendable {
    let session: SessionSnapshot
    let tasks: [TaskSnapshot]
    let analysisReport: SessionAnalysisReport?
}

nonisolated struct DashboardSnapshot: Sendable {
    let subjectCount: Int
    let completedSessionCount: Int
    let recentSubject: SubjectSnapshot?
    let activeSession: SessionSnapshot?
    let pencilStatus: String
    let hasDetectedPencil: Bool
}

nonisolated enum SessionFilter: Int, CaseIterable, Sendable {
    case all
    case active
    case completed
    case abandoned

    var title: String {
        switch self {
        case .all: "全部"
        case .active: "进行中"
        case .completed: "已完成"
        case .abandoned: "已放弃"
        }
    }
}

nonisolated struct AppSettingsSnapshot: Sendable {
    var largeModelEnabled: Bool
    var endpoint: String
    var model: String
    var apiKey: String

    var configurationIsReady: Bool {
        LargeModelConfiguration(
            isEnabled: largeModelEnabled,
            endpoint: endpoint,
            apiKey: apiKey,
            model: model
        ).isReady
    }
}

nonisolated struct TaskRunContext: Sendable {
    let sessionID: UUID
    let taskID: UUID
    let taskNumber: Int
    let totalTasks: Int
    let overallDuration: TimeInterval
    let definition: ResearchTaskDefinition
}

nonisolated enum TaskRunPhase: Equatable, Sendable {
    case ready
    case recording
    case review
    case saving(String)
    case completed
    case failed(String)
}

nonisolated struct TaskRunViewState: Equatable, Sendable {
    var phase: TaskRunPhase
    var elapsed: TimeInterval
    var sampleCount: Int
    var tapCount: Int
    var strokeCount: Int
    var overallRemainingTime: TimeInterval?
    var pencilIsAway: Bool
}

@MainActor
protocol TaskRunControlling: AnyObject {
    var context: TaskRunContext { get }
    var state: TaskRunViewState { get }
    var onStateChange: ((TaskRunViewState) -> Void)? { get set }

    func start() async
    func receive(samples: [PencilSample])
    func receive(updates: [PencilSample])
    func receive(tap: TapEvent)
    func recordPencilDetection(_ source: PencilMonitor.DetectionSource)
    func updateCanvasSize(_ size: CGSize)
    func finish()
    func redo() async
    func save() async
    func exit() async
}

@MainActor
protocol AppBackend: AnyObject {
    func bootstrap() throws
    func dashboard() throws -> DashboardSnapshot

    func subjects(matching query: String) throws -> [SubjectSnapshot]
    func subject(id: UUID) throws -> SubjectSnapshot?
    func subjectSessions(subjectID: UUID) throws -> [SessionSnapshot]
    @discardableResult
    func saveSubject(id: UUID?, input: SubjectFormInput) throws -> UUID
    func deleteSubject(id: UUID) async throws

    func sessions(filter: SessionFilter, matching query: String) throws -> [SessionSnapshot]
    func sessionDetail(id: UUID) throws -> SessionDetailSnapshot?
    @discardableResult
    func createSession(subjectID: UUID, mode: TestMode) throws -> UUID
    func renameSession(id: UUID, name: String?) throws
    func abandonSession(id: UUID) throws
    func deleteSession(id: UUID) async throws
    func analyzeSession(id: UUID, force: Bool) async throws -> SessionAnalysisReport
    func exportSession(id: UUID) async throws -> URL
    func previewURL(taskID: UUID) async -> URL?
    func makeTaskRunner(sessionID: UUID, taskID: UUID) throws -> any TaskRunControlling

    func settings() -> AppSettingsSnapshot
    func saveSettings(_ settings: AppSettingsSnapshot) throws
    func testLargeModel(settings: AppSettingsSnapshot) async throws -> String
    func listModels(settings: AppSettingsSnapshot) async throws -> [String]
}
