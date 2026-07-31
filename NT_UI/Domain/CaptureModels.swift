import CoreGraphics
import Foundation

nonisolated enum InputDeviceType: String, Codable {
    case pencil
    case finger
    case simulator
}

nonisolated enum SamplePhase: String, Codable {
    case began
    case moved
    case stationary
    case ended
    case cancelled
    case hover
}

nonisolated struct PencilSample: Codable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var timestamp: TimeInterval
    var x: Double
    var y: Double
    var normalizedX: Double
    var normalizedY: Double
    var canvasWidth: Double
    var canvasHeight: Double
    var strokeID: Int
    var phase: SamplePhase
    var force: Double
    var maximumPossibleForce: Double
    var normalizedForce: Double
    var altitudeAngle: Double
    var azimuthAngle: Double
    var rollAngle: Double
    var majorRadius: Double
    var inputDevice: InputDeviceType
    var wasCoalesced: Bool
    var estimatedPropertiesRawValue: Int
    var estimationUpdateIndex: Int?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        timestamp: TimeInterval,
        point: CGPoint,
        canvasSize: CGSize,
        strokeID: Int,
        phase: SamplePhase,
        force: CGFloat,
        maximumPossibleForce: CGFloat,
        altitudeAngle: CGFloat,
        azimuthAngle: CGFloat,
        rollAngle: CGFloat,
        majorRadius: CGFloat,
        inputDevice: InputDeviceType,
        wasCoalesced: Bool,
        estimatedPropertiesRawValue: Int,
        estimationUpdateIndex: Int?
    ) {
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        x = point.x
        y = point.y
        normalizedX = canvasSize.width > 0 ? point.x / canvasSize.width : 0
        normalizedY = canvasSize.height > 0 ? point.y / canvasSize.height : 0
        canvasWidth = canvasSize.width
        canvasHeight = canvasSize.height
        self.strokeID = strokeID
        self.phase = phase
        self.force = force
        self.maximumPossibleForce = maximumPossibleForce
        normalizedForce = maximumPossibleForce > 0 ? force / maximumPossibleForce : 0
        self.altitudeAngle = altitudeAngle
        self.azimuthAngle = azimuthAngle
        self.rollAngle = rollAngle
        self.majorRadius = majorRadius
        self.inputDevice = inputDevice
        self.wasCoalesced = wasCoalesced
        self.estimatedPropertiesRawValue = estimatedPropertiesRawValue
        self.estimationUpdateIndex = estimationUpdateIndex
    }
}

nonisolated enum TapTarget: String, Codable {
    case left
    case right
    case outside
}

nonisolated struct TapEvent: Codable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var timestamp: TimeInterval
    var sequenceIndex: Int
    var x: Double
    var y: Double
    var normalizedX: Double
    var normalizedY: Double
    var target: TapTarget
    var expectedTarget: TapTarget
    var isCorrect: Bool
    var inputDevice: InputDeviceType

    init(
        id: UUID = UUID(),
        taskID: UUID,
        timestamp: TimeInterval,
        sequenceIndex: Int,
        point: CGPoint,
        canvasSize: CGSize,
        target: TapTarget,
        expectedTarget: TapTarget,
        isCorrect: Bool,
        inputDevice: InputDeviceType
    ) {
        self.id = id
        self.taskID = taskID
        self.timestamp = timestamp
        self.sequenceIndex = sequenceIndex
        x = point.x
        y = point.y
        normalizedX = canvasSize.width > 0 ? point.x / canvasSize.width : 0
        normalizedY = canvasSize.height > 0 ? point.y / canvasSize.height : 0
        self.target = target
        self.expectedTarget = expectedTarget
        self.isCorrect = isCorrect
        self.inputDevice = inputDevice
    }
}

nonisolated struct TaskFeatureSet: Codable, Sendable {
    static let algorithmVersion = "1.0.0"

    var taskKind: ResearchTaskKind
    var algorithmVersion: String
    var values: [String: Double]
    var qualityFlags: [String]

    init(
        taskKind: ResearchTaskKind,
        algorithmVersion: String = TaskFeatureSet.algorithmVersion,
        values: [String: Double] = [:],
        qualityFlags: [String] = []
    ) {
        self.taskKind = taskKind
        self.algorithmVersion = algorithmVersion
        self.values = values
        self.qualityFlags = qualityFlags
    }
}

nonisolated struct ExportManifest: Codable {
    let schemaVersion: String
    let featureAlgorithmVersion: String
    let exportedAt: Date
    let appVersion: String
    let systemVersion: String
    let deviceModel: String
    let subjectID: UUID
    let subjectCode: String
    let sessionID: UUID
    let mode: TestMode
    let taskCount: Int
    let modelVersions: [String: String]
    let modelInputContract: [String: String]
    let coordinateMapping: [String: String]
    let zProxyRule: String
    let qualityFlags: [String]
}

nonisolated struct SubjectExport: Codable {
    let id: UUID
    let code: String
    let age: Int?
    let sex: String
    let dominantHand: String
    let group: String
    let notes: String
}

nonisolated struct SessionExport: Codable {
    let id: UUID
    let recordName: String
    let state: String
    let mode: String
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let tasks: [TaskExport]
}

nonisolated struct TaskExport: Codable {
    let id: UUID
    let taskID: String
    let title: String
    let hand: String
    let state: String
    let attemptCount: Int
    let sampleCount: Int
    let tapCount: Int
    let duration: Double
    let canvasWidth: Double
    let canvasHeight: Double
    let qualityFlags: [String]
}

nonisolated struct RawPointExport: Codable {
    let subjectID: UUID
    let sessionID: UUID
    let taskID: UUID
    let taskType: String
    let hand: String
    let sample: PencilSample
}

nonisolated struct TapEventExport: Codable {
    let subjectID: UUID
    let sessionID: UUID
    let taskID: UUID
    let taskType: String
    let hand: String
    let event: TapEvent
}
