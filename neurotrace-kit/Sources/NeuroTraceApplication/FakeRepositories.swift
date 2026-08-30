import Foundation
import NeuroTraceDomain

public actor FakeSubjectRepository: SubjectRepository {
    private var values: [NeuroTraceDomain.Subject]
    private var continuations: [UUID: AsyncStream<[NeuroTraceDomain.Subject]>.Continuation] = [:]

    public init(values: [NeuroTraceDomain.Subject] = []) { self.values = values }

    public func subjects(matching query: String) -> [NeuroTraceDomain.Subject] {
        query.isEmpty ? values : values.filter { $0.code.localizedCaseInsensitiveContains(query) }
    }

    public func subject(id: UUID) -> NeuroTraceDomain.Subject? { values.first { $0.id == id } }

    public func save(_ subject: NeuroTraceDomain.Subject) {
        values.removeAll { $0.id == subject.id }
        values.insert(subject, at: 0)
        publish()
    }

    public func delete(id: UUID) {
        values.removeAll { $0.id == id }
        publish()
    }

    public func updates() -> AsyncStream<[NeuroTraceDomain.Subject]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(values)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    private func publish() { continuations.values.forEach { $0.yield(values) } }
    private func removeContinuation(id: UUID) { continuations.removeValue(forKey: id) }
}

public actor FakeSessionRepository: SessionRepository {
    private var values: [NeuroTraceDomain.Session]
    public init(values: [NeuroTraceDomain.Session] = []) { self.values = values }

    public func sessions(status: SessionStatus?) -> [NeuroTraceDomain.Session] {
        guard let status else { return values }
        return values.filter { $0.status == status }
    }

    public func session(id: UUID) -> NeuroTraceDomain.Session? { values.first { $0.id == id } }

    public func create(subjectID: UUID, mode: String) -> UUID {
        let id = UUID()
        values.insert(.init(
            id: id,
            subjectID: subjectID,
            name: "",
            mode: mode,
            status: .ready,
            completedTaskCount: 0,
            taskCount: 0,
            updatedAt: .now
        ), at: 0)
        return id
    }

    public func rename(id: UUID, name: String?) throws { try replace(id: id, name: name) }
    public func resume(id: UUID) throws -> NeuroTraceDomain.Session {
        guard let value = values.first(where: { $0.id == id }) else { throw FakeRepositoryError.notFound }
        return value
    }
    public func updateStatus(id: UUID, status: SessionStatus) throws { try replace(id: id, status: status) }
    public func delete(id: UUID) { values.removeAll { $0.id == id } }

    private func replace(id: UUID, name: String? = nil, status: SessionStatus? = nil) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw FakeRepositoryError.notFound }
        let old = values[index]
        values[index] = .init(
            id: old.id,
            subjectID: old.subjectID,
            name: name ?? old.name,
            mode: old.mode,
            status: status ?? old.status,
            completedTaskCount: old.completedTaskCount,
            taskCount: old.taskCount,
            updatedAt: .now
        )
    }
}

public actor FakeCaptureRepository: CaptureRepository {
    private var values: [String: [CapturePoint]] = [:]
    public init() {}
    public func appendRecoveryLog(sessionID: UUID, taskID: UUID, points: [CapturePoint]) {
        values[key(sessionID, taskID), default: []].append(contentsOf: points)
    }
    public func rawPoints(sessionID: UUID, taskID: UUID) -> [CapturePoint] { values[key(sessionID, taskID)] ?? [] }
    public func previewURL(sessionID: UUID, taskID: UUID) -> URL? { nil }
    public func closeRecoveryLog(sessionID: UUID, taskID: UUID) {}
    private func key(_ sessionID: UUID, _ taskID: UUID) -> String { "\(sessionID.uuidString)/\(taskID.uuidString)" }
}

public actor FakeSettingsStore: SettingsStore {
    private var values: [String: String] = [:]
    private var credentials: [String: String] = [:]
    public init() {}
    public func value(for key: String) -> String? { values[key] }
    public func setValue(_ value: String?, for key: String) { values[key] = value }
    public func credential(for key: String) -> String? { credentials[key] }
    public func setCredential(_ value: String?, for key: String) { credentials[key] = value }
}

public enum FakeRepositoryError: Error, Sendable { case notFound }
