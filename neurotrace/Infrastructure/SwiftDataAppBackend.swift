import Foundation
import SwiftData

@MainActor
final class SwiftDataAppBackend: AppBackend {
    private let context: ModelContext
    private let services: AppServices

    init(context: ModelContext, services: AppServices) {
        self.context = context
        self.services = services
    }

    func bootstrap() throws {
        try seedUITestDataIfRequested()
        try services.recoverInterruptedTasks(context: context)
    }

    func dashboard() throws -> DashboardSnapshot {
        let subjects = try fetchSubjects()
        let sessions = try fetchSessions()
        let active = sessions.first { $0.state == .ready || $0.state == .inProgress }
        return DashboardSnapshot(
            subjectCount: subjects.count,
            completedSessionCount: sessions.count { $0.state == .completed },
            recentSubject: subjects.first.map(subjectSnapshot),
            activeSession: active.map(sessionSnapshot),
            pencilStatus: services.pencilMonitor.statusText,
            hasDetectedPencil: services.pencilMonitor.hasDetectedPencil
        )
    }

    func subjects(matching query: String) throws -> [SubjectSnapshot] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fetchSubjects()
            .filter { normalized.isEmpty || $0.code.localizedCaseInsensitiveContains(normalized) }
            .map(subjectSnapshot)
    }

    func subject(id: UUID) throws -> SubjectSnapshot? {
        try findSubject(id: id).map(subjectSnapshot)
    }

    func subjectSessions(subjectID: UUID) throws -> [SessionSnapshot] {
        guard let subject = try findSubject(id: subjectID) else { return [] }
        return subject.sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(sessionSnapshot)
    }

    @discardableResult
    func saveSubject(id: UUID?, input: SubjectFormInput) throws -> UUID {
        let code = input.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw BackendError.validation("受试者编号不能为空。") }
        if let age = input.age, !(1...120).contains(age) {
            throw BackendError.validation("年龄应为 1–120 的整数。")
        }
        let subjects = try fetchSubjects()
        if subjects.contains(where: {
            $0.code.caseInsensitiveCompare(code) == .orderedSame && $0.id != id
        }) {
            throw BackendError.validation("受试者编号已存在。")
        }

        let target: Subject
        if let id, let existing = try findSubject(id: id) {
            target = existing
        } else {
            target = Subject(code: code)
            context.insert(target)
        }
        target.code = code
        target.age = input.age
        target.sex = input.sex
        target.dominantHand = input.dominantHand
        target.researchGroup = input.researchGroup
        target.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.updatedAt = .now
        try context.save()
        return target.id
    }

    func deleteSubject(id: UUID) async throws {
        guard let subject = try findSubject(id: id) else { return }
        for session in subject.sessions {
            try await services.captureStore.removeSession(session.id)
        }
        context.delete(subject)
        try context.save()
    }

    func sessions(filter: SessionFilter, matching query: String) throws -> [SessionSnapshot] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try fetchSessions()
            .filter { session in
                switch filter {
                case .all: true
                case .active: session.state == .ready || session.state == .inProgress
                case .completed: session.state == .completed
                case .abandoned: session.state == .abandoned
                }
            }
            .filter {
                normalized.isEmpty
                    || $0.displayName.localizedCaseInsensitiveContains(normalized)
                    || ($0.subject?.code.localizedCaseInsensitiveContains(normalized) ?? false)
            }
            .map(sessionSnapshot)
    }

    func sessionDetail(id: UUID) throws -> SessionDetailSnapshot? {
        guard let session = try findSession(id: id) else { return nil }
        return SessionDetailSnapshot(
            session: sessionSnapshot(session),
            tasks: session.orderedTasks.map(taskSnapshot),
            analysisReport: session.analysisReport
        )
    }

    @discardableResult
    func createSession(subjectID: UUID, mode: TestMode) throws -> UUID {
        guard let subject = try findSubject(id: subjectID) else {
            throw BackendError.notFound("未找到受试者。")
        }
        return try services.createSession(subject: subject, mode: mode, context: context).id
    }

    func renameSession(id: UUID, name: String?) throws {
        guard let session = try findSession(id: id) else { throw BackendError.notFound("未找到测试。") }
        let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (normalized?.count ?? 0) <= 60 else {
            throw BackendError.validation("名称最多 60 个字符。")
        }
        session.customName = normalized?.isEmpty == false ? normalized : nil
        session.updatedAt = .now
        try context.save()
    }

    func abandonSession(id: UUID) throws {
        guard let session = try findSession(id: id) else { throw BackendError.notFound("未找到测试。") }
        session.tasks.first(where: { $0.state == .inProgress })?.state = .needsRedo
        session.state = .abandoned
        session.updatedAt = .now
        try context.save()
    }

    func deleteSession(id: UUID) async throws {
        guard let session = try findSession(id: id) else { return }
        try await services.delete(session: session, context: context)
    }

    func analyzeSession(id: UUID, force: Bool) async throws -> SessionAnalysisReport {
        guard let session = try findSession(id: id) else { throw BackendError.notFound("未找到测试。") }
        return try await services.analyze(session: session, context: context, force: force)
    }

    func exportSession(id: UUID) async throws -> URL {
        guard let session = try findSession(id: id) else { throw BackendError.notFound("未找到测试。") }
        guard session.state == .completed else { throw BackendError.validation("测试完成后才能导出。") }
        return try await services.exportService.export(session: session)
    }

    func previewURL(taskID: UUID) async -> URL? {
        guard let task = try? findTask(id: taskID) else { return nil }
        return await services.captureStore.absoluteURL(relativePath: task.previewRelativePath)
    }

    func makeTaskRunner(sessionID: UUID, taskID: UUID) throws -> any TaskRunControlling {
        guard let session = try findSession(id: sessionID),
              let task = session.tasks.first(where: { $0.id == taskID }) else {
            throw BackendError.notFound("未找到采集任务。")
        }
        return TaskRunStateMachine(
            session: session,
            task: task,
            context: context,
            services: services
        )
    }

    func settings() -> AppSettingsSnapshot {
        let configuration = LargeModelConfiguration.load()
        return AppSettingsSnapshot(
            largeModelEnabled: configuration.isEnabled,
            endpoint: configuration.endpoint,
            model: configuration.model,
            apiKey: configuration.apiKey
        )
    }

    func saveSettings(_ settings: AppSettingsSnapshot) throws {
        let defaults = UserDefaults.standard
        defaults.set(settings.largeModelEnabled, forKey: LargeModelSettingsKeys.enabled)
        defaults.set(settings.endpoint, forKey: LargeModelSettingsKeys.endpoint)
        defaults.set(settings.model, forKey: LargeModelSettingsKeys.model)
        try SecureAPIKeyStore.save(settings.apiKey)
    }

    func testLargeModel(settings: AppSettingsSnapshot) async throws -> String {
        try await LargeModelClient(configuration: configuration(from: settings)).testConnection()
    }

    func listModels(settings: AppSettingsSnapshot) async throws -> [String] {
        try await LargeModelClient(configuration: configuration(from: settings)).listModels()
    }

    private func configuration(from settings: AppSettingsSnapshot) -> LargeModelConfiguration {
        LargeModelConfiguration(
            isEnabled: settings.largeModelEnabled,
            endpoint: settings.endpoint,
            apiKey: settings.apiKey,
            model: settings.model
        )
    }

    private func fetchSubjects() throws -> [Subject] {
        try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    private func fetchSessions() throws -> [TestSession] {
        try context.fetch(FetchDescriptor<TestSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    private func findSubject(id: UUID) throws -> Subject? {
        try context.fetch(FetchDescriptor<Subject>(predicate: #Predicate { $0.id == id })).first
    }

    private func findSession(id: UUID) throws -> TestSession? {
        try context.fetch(FetchDescriptor<TestSession>(predicate: #Predicate { $0.id == id })).first
    }

    private func findTask(id: UUID) throws -> TaskRecord? {
        try context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func subjectSnapshot(_ subject: Subject) -> SubjectSnapshot {
        SubjectSnapshot(
            id: subject.id,
            code: subject.code,
            age: subject.age,
            sex: subject.sex,
            dominantHand: subject.dominantHand,
            researchGroup: subject.researchGroup,
            notes: subject.notes,
            sessionCount: subject.sessions.count,
            updatedAt: subject.updatedAt
        )
    }

    private func sessionSnapshot(_ session: TestSession) -> SessionSnapshot {
        SessionSnapshot(
            id: session.id,
            subjectID: session.subject?.id,
            subjectCode: session.subject?.code ?? "未知受试者",
            displayName: session.displayName,
            hasCustomName: session.hasCustomName,
            mode: session.mode,
            state: session.state,
            createdAt: session.createdAt,
            startedAt: session.startedAt,
            updatedAt: session.updatedAt,
            completedAt: session.completedAt,
            completedTaskCount: session.completedTaskCount,
            taskCount: session.tasks.count,
            hasAnalysisReport: session.analysisReport != nil
        )
    }

    private func taskSnapshot(_ task: TaskRecord) -> TaskSnapshot {
        let definition = TaskCatalog.definition(for: task.taskKind)
        return TaskSnapshot(
            id: task.id,
            orderIndex: task.orderIndex,
            kind: task.taskKind,
            title: definition.title,
            instruction: definition.instruction,
            hand: definition.hand,
            state: task.state,
            sampleCount: task.sampleCount,
            tapCount: task.tapCount,
            duration: task.duration,
            attemptCount: task.attemptCount,
            featureValues: task.features?.values ?? [:],
            qualityFlags: task.qualityFlags,
            hasPreview: task.previewRelativePath != nil
        )
    }

    private func seedUITestDataIfRequested() throws {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let active = arguments.contains("-uiTestSeedActiveSession")
        let interrupted = arguments.contains("-uiTestSeedInterruptedSession")
        guard active || interrupted else { return }
        for subject in try fetchSubjects() { context.delete(subject) }
        try context.save()
        let subject = Subject(code: "S-UI-001")
        context.insert(subject)
        let session = try services.createSession(subject: subject, mode: .quick, context: context)
        if interrupted, let firstTask = session.orderedTasks.first {
            firstTask.state = .inProgress
            session.state = .inProgress
            session.startedAt = .now
            try context.save()
        }
        #endif
    }
}

nonisolated enum BackendError: LocalizedError {
    case validation(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .notFound(let message): message
        }
    }
}
