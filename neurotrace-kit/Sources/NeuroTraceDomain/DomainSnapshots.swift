import Foundation

public struct Subject: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let code: String
    public let age: Int?
    public let sex: String
    public let dominantHand: String
    public let researchGroup: String
    public let notes: String

    public init(
        id: UUID,
        code: String,
        age: Int?,
        sex: String,
        dominantHand: String,
        researchGroup: String,
        notes: String
    ) {
        self.id = id
        self.code = code
        self.age = age
        self.sex = sex
        self.dominantHand = dominantHand
        self.researchGroup = researchGroup
        self.notes = notes
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case ready
    case inProgress
    case completed
    case abandoned
}

public struct Session: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let subjectID: UUID
    public let name: String
    public let mode: String
    public let status: SessionStatus
    public let completedTaskCount: Int
    public let taskCount: Int
    public let updatedAt: Date

    public init(
        id: UUID,
        subjectID: UUID,
        name: String,
        mode: String,
        status: SessionStatus,
        completedTaskCount: Int,
        taskCount: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.subjectID = subjectID
        self.name = name
        self.mode = mode
        self.status = status
        self.completedTaskCount = completedTaskCount
        self.taskCount = taskCount
        self.updatedAt = updatedAt
    }
}

public struct ResearchTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: String
    public let title: String
    public let instruction: String
    public let status: String

    public init(id: UUID, kind: String, title: String, instruction: String, status: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.instruction = instruction
        self.status = status
    }
}

public struct CapturePoint: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let force: Double
    public let altitude: Double
    public let azimuth: Double

    public init(
        timestamp: TimeInterval,
        x: Double,
        y: Double,
        force: Double,
        altitude: Double,
        azimuth: Double
    ) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

public struct AnalysisReport: Equatable, Sendable {
    public let generatedAt: Date
    public let summary: String
    public let warnings: [String]
    public let taskSummaries: [String]

    public init(generatedAt: Date, summary: String, warnings: [String], taskSummaries: [String]) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.warnings = warnings
        self.taskSummaries = taskSummaries
    }
}

public enum NeuroTraceDataContract {
    public static let schemaVersion = "2.0.0"
}
