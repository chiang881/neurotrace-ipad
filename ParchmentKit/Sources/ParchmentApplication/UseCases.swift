import Foundation
import ParchmentDomain

public struct Dashboard: Equatable, Sendable {
    public let subjectCount: Int
    public let completedSessionCount: Int
    public let activeSession: ParchmentDomain.Session?
    public let recentSubject: ParchmentDomain.Subject?

    public init(
        subjectCount: Int,
        completedSessionCount: Int,
        activeSession: ParchmentDomain.Session?,
        recentSubject: ParchmentDomain.Subject?
    ) {
        self.subjectCount = subjectCount
        self.completedSessionCount = completedSessionCount
        self.activeSession = activeSession
        self.recentSubject = recentSubject
    }
}

public struct LoadDashboardUseCase: Sendable {
    private let subjects: any SubjectRepository
    private let sessions: any SessionRepository

    public init(subjects: any SubjectRepository, sessions: any SessionRepository) {
        self.subjects = subjects
        self.sessions = sessions
    }

    public func callAsFunction() async throws -> Dashboard {
        async let subjectValues = subjects.subjects(matching: "")
        async let sessionValues = sessions.sessions(status: nil)
        let (allSubjects, allSessions) = try await (subjectValues, sessionValues)
        return Dashboard(
            subjectCount: allSubjects.count,
            completedSessionCount: allSessions.count { $0.status == .completed },
            activeSession: allSessions.first { $0.status == .ready || $0.status == .inProgress },
            recentSubject: allSubjects.first
        )
    }
}

public struct ManageSubjectUseCase: Sendable {
    private let repository: any SubjectRepository

    public init(repository: any SubjectRepository) { self.repository = repository }
    public func list(query: String = "") async throws -> [ParchmentDomain.Subject] {
        try await repository.subjects(matching: query)
    }
    public func save(_ subject: ParchmentDomain.Subject) async throws { try await repository.save(subject) }
    public func delete(id: UUID) async throws { try await repository.delete(id: id) }
}

public struct CreateSessionUseCase: Sendable {
    private let repository: any SessionRepository
    public init(repository: any SessionRepository) { self.repository = repository }
    public func callAsFunction(subjectID: UUID, mode: String) async throws -> UUID {
        try await repository.create(subjectID: subjectID, mode: mode)
    }
}

public struct ResumeSessionUseCase: Sendable {
    private let repository: any SessionRepository
    public init(repository: any SessionRepository) { self.repository = repository }
    public func callAsFunction(id: UUID) async throws -> ParchmentDomain.Session {
        try await repository.resume(id: id)
    }
}

public struct RunTaskUseCase: Sendable {
    public private(set) var stateMachine: TaskRunStateMachine
    public init(stateMachine: TaskRunStateMachine = .init()) { self.stateMachine = stateMachine }
    @discardableResult
    public mutating func send(_ action: TaskRunAction) throws -> TaskRunState {
        try stateMachine.send(action)
    }
}

public struct AnalyzeSessionUseCase: Sendable {
    private let gateway: any AnalysisGateway
    public init(gateway: any AnalysisGateway) { self.gateway = gateway }
    public func callAsFunction(id: UUID) async throws -> AnalysisReport { try await gateway.analyze(sessionID: id) }
}

public struct ExportSessionUseCase: Sendable {
    private let exporter: any Exporting
    public init(exporter: any Exporting) { self.exporter = exporter }
    public func callAsFunction(id: UUID) async throws -> URL {
        try await exporter.export(sessionID: id, schemaVersion: ParchmentDataContract.schemaVersion)
    }
}
