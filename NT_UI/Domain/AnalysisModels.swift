import Foundation

nonisolated enum RiskLevel: String, Codable, CaseIterable {
    case low = "低关注"
    case medium = "中等关注"
    case high = "高关注"
    case unknown = "无法评估"

    static func from(score: Double?) -> RiskLevel {
        guard let score else { return .unknown }
        if score >= 70 { return .high }
        if score >= 35 { return .medium }
        return .low
    }
}

nonisolated enum AnalysisStatus: String, Codable {
    case completed = "已完成"
    case partial = "部分完成"
    case failed = "失败"
}

nonisolated struct AnalysisProgressState: Equatable, Sendable {
    var completedUnits: Int
    var totalUnits: Int
    var message: String

    var fraction: Double {
        guard totalUnits > 0 else { return 0 }
        return min(max(Double(completedUnits) / Double(totalUnits), 0), 1)
    }
}

typealias AnalysisProgressHandler = @MainActor @Sendable (AnalysisProgressState) -> Void

nonisolated enum LargeModelAnalysisKind: String, Codable {
    case image = "图像分析"
    case data = "数据分析"
    case overall = "综合分析"
}

nonisolated struct SessionAnalysisReport: Codable {
    static let schemaVersion = "1.0.0"

    var schemaVersion: String
    var generatedAt: Date
    var status: AnalysisStatus
    var overallRiskScore: Double?
    var overallRiskLevel: RiskLevel
    var overallLargeModelResult: LargeModelAnalysisResult?
    var summary: String
    var warnings: [String]
    var taskReports: [TaskAnalysisReport]

    init(
        schemaVersion: String = SessionAnalysisReport.schemaVersion,
        generatedAt: Date = .now,
        status: AnalysisStatus,
        overallRiskScore: Double?,
        overallLargeModelResult: LargeModelAnalysisResult? = nil,
        summary: String,
        warnings: [String],
        taskReports: [TaskAnalysisReport]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.status = status
        self.overallRiskScore = overallRiskScore
        overallRiskLevel = RiskLevel.from(score: overallRiskScore)
        self.overallLargeModelResult = overallLargeModelResult
        self.summary = summary
        self.warnings = warnings
        self.taskReports = taskReports
    }
}

nonisolated struct TaskAnalysisReport: Codable, Identifiable {
    var id: String { taskKind.rawValue }

    var taskKind: ResearchTaskKind
    var title: String
    var hand: String
    var riskScore: Double?
    var riskLevel: RiskLevel
    var featureHighlights: [String: Double]
    var localModelResults: [LocalModelAnalysisResult]
    var largeModelResults: [LargeModelAnalysisResult]
    var notes: [String]

    init(
        taskKind: ResearchTaskKind,
        title: String,
        hand: String,
        riskScore: Double? = nil,
        featureHighlights: [String: Double] = [:],
        localModelResults: [LocalModelAnalysisResult] = [],
        largeModelResults: [LargeModelAnalysisResult] = [],
        notes: [String] = []
    ) {
        self.taskKind = taskKind
        self.title = title
        self.hand = hand
        self.riskScore = riskScore
        riskLevel = RiskLevel.from(score: riskScore)
        self.featureHighlights = featureHighlights
        self.localModelResults = localModelResults
        self.largeModelResults = largeModelResults
        self.notes = notes
    }
}

nonisolated struct LocalModelAnalysisResult: Codable, Identifiable {
    var id: String
    var modelName: String
    var scope: String
    var predictedLabel: String?
    var probability: Double?
    var riskScore: Double?
    var riskLevel: RiskLevel
    var summary: String
    var featureCount: Int?
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        modelName: String,
        scope: String,
        predictedLabel: String? = nil,
        probability: Double? = nil,
        summary: String,
        featureCount: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.modelName = modelName
        self.scope = scope
        self.predictedLabel = predictedLabel
        self.probability = probability
        riskScore = probability.map { min(max($0 * 100, 0), 100) }
        riskLevel = RiskLevel.from(score: riskScore)
        self.summary = summary
        self.featureCount = featureCount
        self.errorMessage = errorMessage
    }
}

nonisolated struct LargeModelAnalysisResult: Codable, Identifiable {
    var id: String
    var kind: LargeModelAnalysisKind
    var modelName: String
    var promptFocus: String
    var summary: String
    var findings: [String]
    var riskScore: Double?
    var riskLevel: RiskLevel
    var rawText: String?
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        kind: LargeModelAnalysisKind,
        modelName: String,
        promptFocus: String,
        summary: String,
        findings: [String] = [],
        riskScore: Double? = nil,
        rawText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.modelName = modelName
        self.promptFocus = promptFocus
        self.summary = summary
        self.findings = findings
        self.riskScore = riskScore
        riskLevel = RiskLevel.from(score: riskScore)
        self.rawText = rawText
        self.errorMessage = errorMessage
    }
}
