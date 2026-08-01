import Foundation
import SwiftData

nonisolated enum SubjectSex: String, Codable, CaseIterable, Identifiable {
    case male = "男"
    case female = "女"
    case other = "其他"
    case unspecified = "未填写"

    var id: String { rawValue }
}

nonisolated enum DominantHand: String, Codable, CaseIterable, Identifiable {
    case left = "左手"
    case right = "右手"
    case ambidextrous = "双手"
    case unspecified = "未填写"

    var id: String { rawValue }
}

nonisolated enum ResearchGroup: String, Codable, CaseIterable, Identifiable {
    case healthyControl = "健康对照"
    case parkinsons = "帕金森病"
    case mildCognitiveImpairment = "轻度认知障碍"
    case alzheimers = "阿尔茨海默病"
    case other = "其他"
    case unknown = "未知"

    var id: String { rawValue }
}

nonisolated enum TestMode: String, Codable, CaseIterable, Identifiable {
    case quick = "快速模式"
    case full = "完整模式"

    var id: String { rawValue }

    var estimatedDuration: String {
        switch self {
        case .quick: "约 4–6 分钟"
        case .full: "约 8–12 分钟"
        }
    }

    /// The session-wide countdown begins with the first task. Passing zero is
    /// allowed and displayed as overtime so research collection is never cut off.
    var overallDuration: TimeInterval {
        switch self {
        case .quick: 6 * 60
        case .full: 12 * 60
        }
    }
}

nonisolated enum SessionState: String, Codable {
    case ready
    case inProgress
    case completed
    case abandoned

    var title: String {
        switch self {
        case .ready: "未开始"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .abandoned: "已放弃"
        }
    }
}

nonisolated enum TaskState: String, Codable {
    case pending
    case inProgress
    case needsRedo
    case completed

    var title: String {
        switch self {
        case .pending: "未开始"
        case .inProgress: "进行中"
        case .needsRedo: "需要重做"
        case .completed: "已完成"
        }
    }
}

nonisolated enum TestHand: String, Codable {
    case left = "左手"
    case right = "右手"
    case none = "无"
}

nonisolated enum ResearchTaskKind: String, Codable, CaseIterable, Identifiable {
    case spiralStatic = "spiral_static"
    case spiralDynamic = "spiral_dynamic"
    case spiralRight = "spiral_right"
    case spiralLeft = "spiral_left"
    case holdRight = "hold_right"
    case holdLeft = "hold_left"
    case tappingRight = "tapping_right"
    case tappingLeft = "tapping_left"
    case sentenceCopying = "sentence_copying"
    case waveTracing = "wave_tracing"
    case circleTracing = "circle_tracing"
    case clockCommand = "clock_command"
    case clockCopy = "clock_copy"

    var id: String { rawValue }
}

@Model
final class Subject {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var code: String
    var age: Int?
    var sexRawValue: String
    var dominantHandRawValue: String
    var groupRawValue: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TestSession.subject)
    var sessions: [TestSession]

    init(
        id: UUID = UUID(),
        code: String,
        age: Int? = nil,
        sex: SubjectSex = .unspecified,
        dominantHand: DominantHand = .unspecified,
        group: ResearchGroup = .unknown,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.age = age
        sexRawValue = sex.rawValue
        dominantHandRawValue = dominantHand.rawValue
        groupRawValue = group.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        sessions = []
    }

    var sex: SubjectSex {
        get { SubjectSex(rawValue: sexRawValue) ?? .unspecified }
        set { sexRawValue = newValue.rawValue }
    }

    var dominantHand: DominantHand {
        get { DominantHand(rawValue: dominantHandRawValue) ?? .unspecified }
        set { dominantHandRawValue = newValue.rawValue }
    }

    var researchGroup: ResearchGroup {
        get { ResearchGroup(rawValue: groupRawValue) ?? .unknown }
        set { groupRawValue = newValue.rawValue }
    }
}

@Model
final class TestSession {
    @Attribute(.unique) var id: UUID
    var customName: String?
    var modeRawValue: String
    var stateRawValue: String
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date
    var appVersion: String
    var systemVersion: String
    var deviceModel: String
    var analysisReportData: Data?

    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \TaskRecord.session)
    var tasks: [TaskRecord]

    init(
        id: UUID = UUID(),
        subject: Subject,
        mode: TestMode,
        state: SessionState = .ready,
        createdAt: Date = .now,
        appVersion: String,
        systemVersion: String,
        deviceModel: String
    ) {
        self.id = id
        self.subject = subject
        customName = nil
        modeRawValue = mode.rawValue
        stateRawValue = state.rawValue
        self.createdAt = createdAt
        updatedAt = createdAt
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
        analysisReportData = nil
        tasks = []
    }

    var mode: TestMode {
        get { TestMode(rawValue: modeRawValue) ?? .full }
        set { modeRawValue = newValue.rawValue }
    }

    var state: SessionState {
        get { SessionState(rawValue: stateRawValue) ?? .ready }
        set { stateRawValue = newValue.rawValue }
    }

    var displayName: String {
        normalizedCustomName ?? subject?.code ?? "未知受试者"
    }

    var hasCustomName: Bool {
        normalizedCustomName != nil
    }

    private var normalizedCustomName: String? {
        guard let customName else { return nil }
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var orderedTasks: [TaskRecord] {
        tasks.sorted { $0.orderIndex < $1.orderIndex }
    }

    var completedTaskCount: Int {
        tasks.count { $0.state == .completed }
    }

    var nextTask: TaskRecord? {
        orderedTasks.first { $0.state != .completed }
    }

    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTaskCount) / Double(tasks.count)
    }

    var analysisReport: SessionAnalysisReport? {
        get {
            guard let analysisReportData else { return nil }
            return try? JSONDecoder.parchment.decode(SessionAnalysisReport.self, from: analysisReportData)
        }
        set {
            analysisReportData = try? newValue.map { try JSONEncoder.parchment.encode($0) }
        }
    }
}

@Model
final class TaskRecord {
    @Attribute(.unique) var id: UUID
    var taskKindRawValue: String
    var stateRawValue: String
    var orderIndex: Int
    var attemptCount: Int
    var sampleCount: Int
    var tapCount: Int
    var duration: Double
    var startedAt: Date?
    var completedAt: Date?
    var canvasWidth: Double
    var canvasHeight: Double
    var samplesRelativePath: String?
    var tapsRelativePath: String?
    var recoveryRelativePath: String?
    var previewRelativePath: String?
    var featuresData: Data?
    var qualityFlagsData: Data?

    var session: TestSession?

    init(
        id: UUID = UUID(),
        taskKind: ResearchTaskKind,
        orderIndex: Int,
        state: TaskState = .pending
    ) {
        self.id = id
        taskKindRawValue = taskKind.rawValue
        stateRawValue = state.rawValue
        self.orderIndex = orderIndex
        attemptCount = 0
        sampleCount = 0
        tapCount = 0
        duration = 0
        canvasWidth = 0
        canvasHeight = 0
    }

    var taskKind: ResearchTaskKind {
        get { ResearchTaskKind(rawValue: taskKindRawValue) ?? .spiralStatic }
        set { taskKindRawValue = newValue.rawValue }
    }

    var state: TaskState {
        get { TaskState(rawValue: stateRawValue) ?? .pending }
        set { stateRawValue = newValue.rawValue }
    }

    var features: TaskFeatureSet? {
        get {
            guard let featuresData else { return nil }
            return try? JSONDecoder.parchment.decode(TaskFeatureSet.self, from: featuresData)
        }
        set {
            featuresData = try? newValue.map { try JSONEncoder.parchment.encode($0) }
        }
    }

    var qualityFlags: [String] {
        get {
            guard let qualityFlagsData else { return [] }
            return (try? JSONDecoder.parchment.decode([String].self, from: qualityFlagsData)) ?? []
        }
        set {
            qualityFlagsData = try? JSONEncoder.parchment.encode(newValue)
        }
    }
}

nonisolated extension JSONEncoder {
    static var parchment: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

nonisolated extension JSONDecoder {
    static var parchment: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
