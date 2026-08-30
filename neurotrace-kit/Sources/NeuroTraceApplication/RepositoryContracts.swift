import Foundation
import NeuroTraceDomain

public protocol SubjectRepository: Sendable {
    func subjects(matching query: String) async throws -> [NeuroTraceDomain.Subject]
    func subject(id: UUID) async throws -> NeuroTraceDomain.Subject?
    func save(_ subject: NeuroTraceDomain.Subject) async throws
    func delete(id: UUID) async throws
    func updates() async -> AsyncStream<[NeuroTraceDomain.Subject]>
}

public protocol SessionRepository: Sendable {
    func sessions(status: SessionStatus?) async throws -> [NeuroTraceDomain.Session]
    func session(id: UUID) async throws -> NeuroTraceDomain.Session?
    func create(subjectID: UUID, mode: String) async throws -> UUID
    func rename(id: UUID, name: String?) async throws
    func resume(id: UUID) async throws -> NeuroTraceDomain.Session
    func updateStatus(id: UUID, status: SessionStatus) async throws
    func delete(id: UUID) async throws
}

public protocol CaptureRepository: Sendable {
    func appendRecoveryLog(sessionID: UUID, taskID: UUID, points: [CapturePoint]) async throws
    func rawPoints(sessionID: UUID, taskID: UUID) async throws -> [CapturePoint]
    func previewURL(sessionID: UUID, taskID: UUID) async throws -> URL?
    func closeRecoveryLog(sessionID: UUID, taskID: UUID) async throws
}

public protocol AnalysisGateway: Sendable {
    func analyze(sessionID: UUID) async throws -> AnalysisReport
}

public protocol Exporting: Sendable {
    func export(sessionID: UUID, schemaVersion: String) async throws -> URL
}

public protocol SettingsStore: Sendable {
    func value(for key: String) async -> String?
    func setValue(_ value: String?, for key: String) async throws
    func credential(for key: String) async throws -> String?
    func setCredential(_ value: String?, for key: String) async throws
}

public enum TaskRunState: Equatable, Sendable {
    case ready
    case recording
    case review
    case saving
    case completed
    case failed(String)
}

public enum TaskRunAction: Equatable, Sendable {
    case start
    case end(hasValidInput: Bool)
    case redo
    case beginSaving
    case saved
    case fail(String)
    case exit
}

public enum TaskRunTransitionError: LocalizedError, Equatable, Sendable {
    case invalid(from: TaskRunState, action: TaskRunAction)

    public var errorDescription: String? {
        switch self {
        case let .invalid(state, action):
            "Invalid task transition from \(state) using \(action)."
        }
    }
}

public struct TaskRunStateMachine: Sendable {
    public private(set) var state: TaskRunState

    public init(state: TaskRunState = .ready) {
        self.state = state
    }

    @discardableResult
    public mutating func send(_ action: TaskRunAction) throws -> TaskRunState {
        let next: TaskRunState
        switch (state, action) {
        case (.ready, .start): next = .recording
        case (.recording, let .end(hasValidInput)): next = hasValidInput ? .review : .failed("No valid input")
        case (.review, .redo), (.failed, .redo): next = .ready
        case (.review, .beginSaving): next = .saving
        case (.saving, .saved): next = .completed
        case (_, let .fail(message)): next = .failed(message)
        case (.ready, .exit), (.recording, .exit), (.review, .exit), (.failed, .exit):
            next = .failed("Interrupted")
        default:
            throw TaskRunTransitionError.invalid(from: state, action: action)
        }
        state = next
        return next
    }
}
