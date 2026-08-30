import Foundation
import ZIPFoundation

@MainActor
protocol SessionExporting {
    func export(session: TestSession) async throws -> URL
}

@MainActor
final class LocalSessionExporter: SessionExporting {
    private let captureStore: any CaptureStore
    private let fileManager: FileManager

    init(captureStore: any CaptureStore, fileManager: FileManager = .default) {
        self.captureStore = captureStore
        self.fileManager = fileManager
    }

    func export(session: TestSession) async throws -> URL {
        guard let subject = session.subject else { throw ExportError.missingSubject }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let customNameComponent = session.hasCustomName ? "_\(safeFileName(session.displayName))" : ""
        let baseName = "neurotrace_\(safeFileName(subject.code))\(customNameComponent)_\(formatter.string(from: session.createdAt))"

        let exportRoot = fileManager.temporaryDirectory.appending(
            path: "NeuroTraceExports/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let folderURL = exportRoot.appending(path: baseName, directoryHint: .isDirectory)
        let previewsURL = folderURL.appending(path: "preview_images", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: previewsURL, withIntermediateDirectories: true)

        var rawPoints: [RawPointExport] = []
        var tapEvents: [TapEventExport] = []
        var allQualityFlags: [String] = []

        for task in session.orderedTasks {
            let definition = TaskCatalog.definition(for: task.taskKind)
            let samples = try await captureStore.loadSamples(relativePath: task.samplesRelativePath)
            let taps = try await captureStore.loadTaps(relativePath: task.tapsRelativePath)
            rawPoints.append(contentsOf: samples.map {
                RawPointExport(
                    subjectID: subject.id,
                    sessionID: session.id,
                    taskID: task.id,
                    taskType: definition.title,
                    hand: definition.hand.rawValue,
                    sample: $0
                )
            })
            tapEvents.append(contentsOf: taps.map {
                TapEventExport(
                    subjectID: subject.id,
                    sessionID: session.id,
                    taskID: task.id,
                    taskType: definition.title,
                    hand: definition.hand.rawValue,
                    event: $0
                )
            })
            allQualityFlags.append(contentsOf: task.qualityFlags)

            if
                let source = await captureStore.absoluteURL(relativePath: task.previewRelativePath),
                fileManager.fileExists(atPath: source.path)
            {
                let destination = previewsURL.appending(path: "\(task.taskKind.rawValue).png")
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
        }

        let manifest = ExportManifest(
            schemaVersion: "2.0.0",
            featureAlgorithmVersion: TaskFeatureSet.algorithmVersion,
            exportedAt: .now,
            appVersion: session.appVersion,
            systemVersion: session.systemVersion,
            deviceModel: session.deviceModel,
            subjectID: subject.id,
            subjectCode: subject.code,
            sessionID: session.id,
            mode: session.mode,
            taskCount: session.tasks.count,
            modelVersions: [
                "spiral": "ParkinsonSpiralXGBV2",
                "pressure": "ParkinsonXGBoostV2AllCommon"
            ],
            modelInputContract: [
                "spiral": "28 Double features from static spiral testID 0 and dynamic spiral testID 1; threshold 0.45",
                "pressure": "Float32[72] MLMultiArray named features; missing values use Float.nan"
            ],
            coordinateMapping: [
                "x": "normalizedX * 1000",
                "y": "normalizedY * 570",
                "timestamp": "seconds for spiral V2; milliseconds for pressure V2",
                "pressure": "normalizedForce for spiral V2; normalizedForce * 1023 for pressure V2",
                "gripAngle": "altitudeAngle radians for spiral V2; altitudeAngle * 180 / pi * 10 for pressure V2"
            ],
            zProxyRule: "pressure1023 * sin(altitudeAngle); iPad vertical pressure proxy, not the original digitizer Z channel",
            qualityFlags: Array(Set(allQualityFlags)).sorted()
        )
        let subjectExport = SubjectExport(
            id: subject.id,
            code: subject.code,
            age: subject.age,
            sex: subject.sex.rawValue,
            dominantHand: subject.dominantHand.rawValue,
            group: subject.researchGroup.rawValue,
            notes: subject.notes
        )
        let sessionExport = SessionExport(
            id: session.id,
            recordName: session.displayName,
            state: session.state.title,
            mode: session.mode.rawValue,
            createdAt: session.createdAt,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            tasks: session.orderedTasks.map { task in
                let definition = TaskCatalog.definition(for: task.taskKind)
                return TaskExport(
                    id: task.id,
                    taskID: task.taskKind.rawValue,
                    title: definition.title,
                    hand: definition.hand.rawValue,
                    state: task.state.title,
                    attemptCount: task.attemptCount,
                    sampleCount: task.sampleCount,
                    tapCount: task.tapCount,
                    duration: task.duration,
                    canvasWidth: task.canvasWidth,
                    canvasHeight: task.canvasHeight,
                    qualityFlags: task.qualityFlags
                )
            }
        )

        try write(manifest, named: "manifest.json", to: folderURL)
        try write(subjectExport, named: "subject.json", to: folderURL)
        try write(sessionExport, named: "session.json", to: folderURL)
        try write(rawPoints, named: "raw_points.json", to: folderURL)
        try write(tapEvents, named: "tap_events.json", to: folderURL)
        try write(testSummary(session), named: "test_summary.json", to: folderURL)
        if let report = session.analysisReport {
            try write(report, named: "analysis_report.json", to: folderURL)
            try analysisMarkdown(report).write(
                to: folderURL.appending(path: "analysis_report.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        try featuresCSV(session).write(
            to: folderURL.appending(path: "features.csv"),
            atomically: true,
            encoding: .utf8
        )

        let archiveURL = exportRoot.appending(path: "\(baseName).zip")
        try fileManager.zipItem(at: folderURL, to: archiveURL, shouldKeepParent: true, compressionMethod: .deflate)
        return archiveURL
    }

    private func write<T: Encodable>(_ value: T, named name: String, to directory: URL) throws {
        try JSONEncoder.neurotrace.encode(value).write(
            to: directory.appending(path: name),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func testSummary(_ session: TestSession) -> [String: AnyCodableValue] {
        var summary: [String: AnyCodableValue] = [
            "sessionId": .string(session.id.uuidString),
            "recordName": .string(session.displayName),
            "state": .string(session.state.title),
            "completedTaskCount": .number(Double(session.completedTaskCount)),
            "taskCount": .number(Double(session.tasks.count))
        ]
        if let report = session.analysisReport {
            summary["analysisStatus"] = .string(report.status.rawValue)
            summary["overallResearchAttentionLevel"] = .string(report.overallRiskLevel.rawValue)
            summary["overallRiskLevel"] = .string(report.overallRiskLevel.rawValue)
            if let score = report.overallRiskScore {
                summary["overallResearchAttentionScore"] = .number(score)
                summary["overallRiskScore"] = .number(score)
            }
        }
        summary["spiralModelVersion"] = .string("ParkinsonSpiralXGBV2")
        summary["pressureModelVersion"] = .string("ParkinsonXGBoostV2AllCommon")
        summary["pressureSchemaVersion"] = .string("v2_all_common_72_float32")
        summary["coordinateMapping"] = .string("x=normalizedX*1000; y=normalizedY*570")
        summary["zProxyRule"] = .string("pressure1023 * sin(altitudeAngle); iPad proxy, not original digitizer Z")
        for (key, value) in SessionAnalytics.leftRightDifferences(tasks: session.tasks) {
            summary[key] = .number(value)
        }
        return summary
    }

    private func analysisMarkdown(_ report: SessionAnalysisReport) -> String {
        var lines: [String] = [
            "# 分析报告",
            "",
            "- 生成时间：\(report.generatedAt.formatted(date: .numeric, time: .standard))",
            "- 状态：\(report.status.rawValue)",
            "- 综合研究关注分数：\(report.overallRiskScore.map { String(format: "%.0f/100", $0) } ?? "无法评估")",
            "- 研究关注等级：\(report.overallRiskLevel.rawValue)",
            "",
            report.summary,
            ""
        ]
        if let overall = report.overallLargeModelResult {
            lines.append("## Overall 综合分析")
            lines.append("")
            lines.append("- 模型：\(overall.modelName)")
            lines.append("- 结果：\(overall.errorMessage ?? overall.summary)")
            if let riskScore = overall.riskScore {
                lines.append("- overall 研究关注分数：\(String(format: "%.0f/100", riskScore))")
            }
            if !overall.findings.isEmpty {
                lines.append("- 依据：")
                for finding in overall.findings {
                    lines.append("  - \(finding)")
                }
            }
            lines.append("")
        }
        lines.append("## 注意事项")
        lines.append(contentsOf: report.warnings.map { "- \($0)" })
        lines.append("")
        lines.append("## 任务结果")

        for task in report.taskReports {
            lines.append("")
            lines.append("### \(task.hand == "无" ? task.title : "\(task.title) · \(task.hand)")")
            lines.append("- 研究模式分数：\(task.riskScore.map { String(format: "%.0f/100", $0) } ?? "无法评估")")
            lines.append("- 研究关注等级：\(task.riskLevel.rawValue)")
            if !task.localModelResults.isEmpty {
                lines.append("- 本地模型：")
                for result in task.localModelResults {
                    lines.append("  - \(result.modelName)：\(result.errorMessage ?? result.summary)")
                }
            }
            if !task.largeModelResults.isEmpty {
                lines.append("- 大模型：")
                for result in task.largeModelResults {
                    lines.append("  - \(result.userFacingTitle)：\(result.errorMessage ?? result.summary)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func featuresCSV(_ session: TestSession) -> String {
        let fixedColumns = [
            "subjectId", "sessionId", "taskId", "taskType", "hand",
            "algorithmVersion", "qualityFlags"
        ]
        let featureKeys = Set(
            session.tasks.flatMap { $0.features.map { Array($0.values.keys) } ?? [] }
        ).sorted()
        var rows = [(fixedColumns + featureKeys).map(csvEscape).joined(separator: ",")]

        for task in session.orderedTasks {
            let definition = TaskCatalog.definition(for: task.taskKind)
            let featureSet = task.features
            let fixed = [
                session.subject?.id.uuidString ?? "",
                session.id.uuidString,
                task.taskKind.rawValue,
                definition.title,
                definition.hand.rawValue,
                featureSet?.algorithmVersion ?? "",
                (featureSet?.qualityFlags ?? []).joined(separator: "|")
            ]
            let values = featureKeys.map { key in
                featureSet?.values[key].map { String(format: "%.10g", $0) } ?? ""
            }
            rows.append((fixed + values).map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[/\\:*?"<>|]"#,
            with: "_",
            options: .regularExpression
        )
    }
}

enum ExportError: LocalizedError {
    case missingSubject

    var errorDescription: String? {
        switch self {
        case .missingSubject: "测试记录缺少受试者信息。"
        }
    }
}

enum AnyCodableValue: Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .boolean(try container.decode(Bool.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
