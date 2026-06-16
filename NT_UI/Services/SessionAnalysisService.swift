import Foundation

@MainActor
final class SessionAnalysisService {
    private let runner: SessionAnalysisRunner

    init(
        captureStore: any CaptureStore,
        localModelAnalyzer: LocalModelAnalyzer? = nil
    ) {
        runner = SessionAnalysisRunner(
            captureStore: captureStore,
            localModelAnalyzer: localModelAnalyzer ?? LocalModelAnalyzer()
        )
    }

    func analyze(
        session: TestSession,
        progress: AnalysisProgressHandler? = nil
    ) async -> SessionAnalysisReport {
        let snapshot = SessionAnalysisSnapshot(session: session)
        return await runner.analyze(snapshot: snapshot, progress: progress)
    }
}

private actor SessionAnalysisRunner {
    private let captureStore: any CaptureStore
    private let localModelAnalyzer: LocalModelAnalyzer

    init(
        captureStore: any CaptureStore,
        localModelAnalyzer: LocalModelAnalyzer
    ) {
        self.captureStore = captureStore
        self.localModelAnalyzer = localModelAnalyzer
    }

    func analyze(
        snapshot: SessionAnalysisSnapshot,
        progress: AnalysisProgressHandler?
    ) async -> SessionAnalysisReport {
        var warnings = [
            "本报告仅用于研究数据汇总，不构成医学诊断、筛查结论或治疗建议。",
            "本地 Core ML 模型来自小样本内部验证，正式研究前需要真实 iPad 数据和外部验证。"
        ]
        let loaded = await loadTaskInputs(snapshot: snapshot)
        let contexts = loaded.contexts
        warnings.append(contentsOf: loaded.warnings)
        var reports = contexts.map(makeBaseReport)
        let configuration = LargeModelConfiguration.load()
        let totalUnits = max(contexts.count + (configuration.isReady ? 1 : 0), 1)

        await reportProgress(
            progress,
            completed: 0,
            total: totalUnits,
            message: "正在准备评估数据..."
        )

        appendLocalModelResults(contexts: contexts, reports: &reports)
        await appendLargeModelResults(
            contexts: contexts,
            reports: &reports,
            warnings: &warnings,
            configuration: configuration,
            progress: progress,
            totalUnits: totalUnits
        )

        for index in reports.indices {
            refreshRisk(&reports[index])
        }

        let fallbackScore = averageRiskScore(from: reports)
        let overallResult = await makeOverallLargeModelResult(
            reports: reports,
            fallbackScore: fallbackScore,
            warnings: &warnings,
            configuration: configuration,
            progress: progress,
            totalUnits: totalUnits
        )
        let overallScore = overallResult?.riskScore ?? fallbackScore

        let hasTaskErrors = reports.contains { report in
            report.localModelResults.contains { $0.errorMessage != nil }
                || report.largeModelResults.contains { $0.errorMessage != nil }
        }
        let hasOverallError = overallResult?.errorMessage != nil
        let status: AnalysisStatus
        if overallScore == nil, reports.allSatisfy({ $0.localModelResults.isEmpty && $0.largeModelResults.isEmpty }) {
            status = .failed
        } else if hasTaskErrors || hasOverallError || warnings.contains(where: { $0.contains("跳过") }) {
            status = .partial
        } else {
            status = .completed
        }

        let report = SessionAnalysisReport(
            status: status,
            overallRiskScore: overallScore,
            overallLargeModelResult: overallResult,
            summary: makeSummary(
                score: overallScore,
                taskCount: reports.count,
                overallResult: overallResult
            ),
            warnings: warnings,
            taskReports: reports
        )
        await reportProgress(
            progress,
            completed: totalUnits,
            total: totalUnits,
            message: "评估完成"
        )
        return report
    }

    private func loadTaskInputs(
        snapshot: SessionAnalysisSnapshot
    ) async -> (contexts: [AnalysisTaskInput], warnings: [String]) {
        var contexts: [AnalysisTaskInput] = []
        var warnings: [String] = []
        for task in snapshot.completedTasks {
            let definition = TaskCatalog.definition(for: task.kind)
            let samples: [PencilSample]
            let taps: [TapEvent]
            do {
                samples = try await captureStore.loadSamples(relativePath: task.samplesRelativePath)
            } catch {
                samples = []
                warnings.append("\(definition.title) 原始笔迹点读取失败：\(describe(error))")
            }
            do {
                taps = try await captureStore.loadTaps(relativePath: task.tapsRelativePath)
            } catch {
                taps = []
                warnings.append("\(definition.title) 点击事件读取失败：\(describe(error))")
            }
            contexts.append(AnalysisTaskInput(
                task: task,
                definition: definition,
                samples: samples,
                taps: taps,
                previewURL: await captureStore.absoluteURL(relativePath: task.previewRelativePath),
                features: task.features
            ))
        }
        return (contexts, warnings)
    }

    private func makeBaseReport(_ input: AnalysisTaskInput) -> TaskAnalysisReport {
        TaskAnalysisReport(
            taskKind: input.definition.kind,
            title: input.definition.title,
            hand: input.definition.hand.rawValue,
            featureHighlights: featureHighlights(input.features),
            notes: input.task.qualityFlags
        )
    }

    private func appendLocalModelResults(
        contexts: [AnalysisTaskInput],
        reports: inout [TaskAnalysisReport]
    ) {
        let spiralStatic = contexts.first { $0.definition.kind == .spiralStatic }?.samples ?? []
        let spiralDynamic = contexts.first { $0.definition.kind == .spiralDynamic }?.samples ?? []
        guard !spiralStatic.isEmpty, !spiralDynamic.isEmpty else {
            return
        }

        let spiralResult = localModelAnalyzer.analyzeSpiralV2(
            staticSamples: spiralStatic,
            dynamicSamples: spiralDynamic
        )
        append(spiralResult, to: .spiralStatic, reports: &reports)
        append(spiralResult, to: .spiralDynamic, reports: &reports)

        let pressureResult = localModelAnalyzer.analyzePressureV2(
            staticSamples: spiralStatic,
            dynamicSamples: spiralDynamic
        )
        append(pressureResult, to: .spiralStatic, reports: &reports)
        append(pressureResult, to: .spiralDynamic, reports: &reports)
    }

    private func appendLargeModelResults(
        contexts: [AnalysisTaskInput],
        reports: inout [TaskAnalysisReport],
        warnings: inout [String],
        configuration: LargeModelConfiguration,
        progress: AnalysisProgressHandler?,
        totalUnits: Int
    ) async {
        guard configuration.isReady else {
            warnings.append("大模型 API 未启用或配置不完整，已跳过所有图片、数据和 overall 综合分析。")
            for (index, context) in contexts.enumerated() {
                await reportProgress(
                    progress,
                    completed: index + 1,
                    total: totalUnits,
                    message: "已完成 \(context.definition.title) 的本地评估"
                )
            }
            return
        }

        let client = LargeModelClient(configuration: configuration)
        for (index, context) in contexts.enumerated() {
            if
                let previewURL = context.previewURL,
                FileManager.default.fileExists(atPath: previewURL.path)
            {
                do {
                    let imageData = try Data(contentsOf: previewURL, options: [.mappedIfSafe])
                    let parsed = try await client.analyzeImage(
                        pngData: imageData,
                        prompt: imagePrompt(for: context)
                    )
                    append(
                        LargeModelAnalysisResult(
                            kind: .image,
                            modelName: configuration.model,
                            promptFocus: imageFocus(for: context.definition.kind),
                            summary: parsed.summary,
                            findings: parsed.findings,
                            riskScore: parsed.riskScore,
                            rawText: parsed.rawText
                        ),
                        to: context.definition.kind,
                        reports: &reports
                    )
                } catch {
                    let result = LargeModelAnalysisResult(
                        kind: .image,
                        modelName: configuration.model,
                        promptFocus: imageFocus(for: context.definition.kind),
                        summary: "图像大模型分析失败。",
                        errorMessage: describe(error)
                    )
                    append(result, to: context.definition.kind, reports: &reports)
                }
            }

            if usesDataLargeModel(context.definition.kind) {
                do {
                    let parsed = try await client.analyzeText(prompt: dataPrompt(for: context))
                    append(
                        LargeModelAnalysisResult(
                            kind: .data,
                            modelName: configuration.model,
                            promptFocus: "触屏敲击节律、准确率、速度衰减和左右交替错误",
                            summary: parsed.summary,
                            findings: parsed.findings,
                            riskScore: parsed.riskScore,
                            rawText: parsed.rawText
                        ),
                        to: context.definition.kind,
                        reports: &reports
                    )
                } catch {
                    let result = LargeModelAnalysisResult(
                        kind: .data,
                        modelName: configuration.model,
                        promptFocus: "触屏敲击特征数据",
                        summary: "数据大模型分析失败。",
                        errorMessage: describe(error)
                    )
                    append(result, to: context.definition.kind, reports: &reports)
                }
            }

            await reportProgress(
                progress,
                completed: index + 1,
                total: totalUnits,
                message: "已完成 \(context.definition.title) 的评估"
            )
        }
    }

    private func makeOverallLargeModelResult(
        reports: [TaskAnalysisReport],
        fallbackScore: Double?,
        warnings: inout [String],
        configuration: LargeModelConfiguration,
        progress: AnalysisProgressHandler?,
        totalUnits: Int
    ) async -> LargeModelAnalysisResult? {
        guard configuration.isReady else { return nil }
        await reportProgress(
            progress,
            completed: max(totalUnits - 1, 0),
            total: totalUnits,
            message: "正在进行大模型 overall 综合评估..."
        )

        do {
            let parsed = try await LargeModelClient(configuration: configuration)
                .analyzeText(prompt: overallPrompt(reports: reports, fallbackScore: fallbackScore))
            return LargeModelAnalysisResult(
                kind: .overall,
                modelName: configuration.model,
                promptFocus: "基于所有任务、本地模型、逐项大模型分析和结构化特征输出最终研究关注分数",
                summary: parsed.summary,
                findings: parsed.findings,
                riskScore: parsed.riskScore,
                rawText: parsed.rawText
            )
        } catch {
            warnings.append("大模型 overall 综合分析失败，综合研究关注分数已回退到逐项模型分数均值。")
            return LargeModelAnalysisResult(
                kind: .overall,
                modelName: configuration.model,
                promptFocus: "所有任务综合研究关注分数",
                summary: "大模型 overall 综合分析失败。",
                errorMessage: describe(error)
            )
        }
    }

    private func reportProgress(
        _ progress: AnalysisProgressHandler?,
        completed: Int,
        total: Int,
        message: String
    ) async {
        guard let progress else { return }
        await progress(AnalysisProgressState(
            completedUnits: completed,
            totalUnits: total,
            message: message
        ))
    }

    private func append(
        _ result: LocalModelAnalysisResult,
        to kind: ResearchTaskKind,
        reports: inout [TaskAnalysisReport]
    ) {
        guard let index = reports.firstIndex(where: { $0.taskKind == kind }) else { return }
        reports[index].localModelResults.append(result)
    }

    private func append(
        _ result: LargeModelAnalysisResult,
        to kind: ResearchTaskKind,
        reports: inout [TaskAnalysisReport]
    ) {
        guard let index = reports.firstIndex(where: { $0.taskKind == kind }) else { return }
        reports[index].largeModelResults.append(result)
    }

    private func refreshRisk(_ report: inout TaskAnalysisReport) {
        let scores = report.localModelResults.compactMap(\.riskScore)
            + report.largeModelResults.compactMap(\.riskScore)
        report.riskScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        report.riskLevel = RiskLevel.from(score: report.riskScore)
    }

    private func averageRiskScore(from reports: [TaskAnalysisReport]) -> Double? {
        let scoredReports = reports.compactMap(\.riskScore)
        return scoredReports.isEmpty
            ? nil
            : scoredReports.reduce(0, +) / Double(scoredReports.count)
    }

    private func usesDataLargeModel(_ kind: ResearchTaskKind) -> Bool {
        kind == .tappingRight || kind == .tappingLeft
    }

    private func featureHighlights(_ features: TaskFeatureSet?) -> [String: Double] {
        guard let values = features?.values else { return [:] }
        let preferredKeys = [
            "duration",
            "pointCount",
            "tapCount",
            "accuracy",
            "meanTapInterval",
            "rhythmInstability",
            "lateSpeedDecline",
            "alternationErrorCount",
            "forceMean",
            "forceStd",
            "templateErrorMean",
            "tremorPower3to8Hz",
            "tremorPower4to6Hz",
            "micrographiaIndex",
            "meanStrokeHeight",
            "closureError",
            "meanRadius",
            "normalizedChamferSimilarity"
        ]
        let selected = preferredKeys.reduce(into: [String: Double]()) { partial, key in
            if let value = values[key] {
                partial[key] = value
            }
        }
        if !selected.isEmpty {
            return selected
        }
        return Dictionary(uniqueKeysWithValues: values.keys.sorted().prefix(10).map {
            ($0, values[$0] ?? 0)
        })
    }

    private func imagePrompt(for context: AnalysisTaskInput) -> String {
        """
        请分析这张 \(context.definition.title) 的测试结果图片。

        重点：\(imageFocus(for: context.definition.kind))

        已计算特征：
        \(featureLines(context.features))

        输出严格 JSON，不要包裹 Markdown：
        {
          "summary": "一句话研究性总结",
          "findings": ["最多 5 条可观察依据"],
          "risk_score": 0 到 100 的研究关注分数
        }
        risk_score 越高表示越需要研究人员复核；不要给医学诊断、疾病风险或治疗建议。
        """
    }

    private func dataPrompt(for context: AnalysisTaskInput) -> String {
        """
        请基于触屏敲击任务的结构化特征做研究性分析。

        任务：\(context.definition.title)\(context.definition.hand == .none ? "" : " · \(context.definition.hand.rawValue)")
        点击事件数：\(context.taps.count)

        特征：
        \(featureLines(context.features))

        请关注节律不稳定、速度衰减、准确率、交替错误。输出严格 JSON，不要包裹 Markdown：
        {
          "summary": "一句话研究性总结",
          "findings": ["最多 5 条依据"],
          "risk_score": 0 到 100 的研究关注分数
        }
        risk_score 越高表示越需要研究人员复核；不要给医学诊断、疾病风险或治疗建议。
        """
    }

    private func overallPrompt(
        reports: [TaskAnalysisReport],
        fallbackScore: Double?
    ) -> String {
        """
        请作为 overall 综合分析模型，基于所有任务结果给出最终研究关注分数。

        要求：
        1. 综合所有任务，不要只平均分数；需要考虑任务质量、左右差异、图像/数据/本地模型之间是否一致。
        2. 对螺旋、静止保持、触屏敲击、短句抄写、波浪线、圆形、画钟分别给出权重判断。
        3. 最终 risk_score 是报告最终研究关注分数，范围 0 到 100，越高表示越需要研究人员复核。
        4. 只能给研究性观察，不给医学诊断、疾病风险或治疗建议。

        逐项结果：
        \(overallTaskLines(reports))

        逐项模型均值（仅供参考，不要机械照搬）：\(fallbackScore.map { String(format: "%.1f", $0) } ?? "无")

        输出严格 JSON，不要包裹 Markdown：
        {
          "summary": "一句话 overall 研究性总结",
          "findings": ["3 到 6 条综合依据"],
          "risk_score": 0 到 100 的最终研究关注分数
        }
        """
    }

    private func overallTaskLines(_ reports: [TaskAnalysisReport]) -> String {
        reports.map { report in
            """
            - \(report.hand == "无" ? report.title : "\(report.title) · \(report.hand)")
              task_risk: \(report.riskScore.map { String(format: "%.1f", $0) } ?? "无")
              features: \(featureSummary(report.featureHighlights))
              local_model: \(report.localModelResults.map { $0.errorMessage ?? $0.summary }.joined(separator: " | "))
              large_model: \(report.largeModelResults.map { $0.errorMessage ?? $0.summary }.joined(separator: " | "))
              notes: \(report.notes.joined(separator: " | "))
            """
        }.joined(separator: "\n")
    }

    private func featureSummary(_ values: [String: Double]) -> String {
        guard !values.isEmpty else { return "无" }
        return values.keys.sorted().map { key in
            "\(key)=\(String(format: "%.5g", values[key] ?? 0))"
        }.joined(separator: ", ")
    }

    private func imageFocus(for kind: ResearchTaskKind) -> String {
        switch kind {
        case .spiralStatic, .spiralRight, .spiralLeft:
            "螺旋描摹是否偏离模板，线条是否抖动、不连续或出现明显空间失控。"
        case .spiralDynamic:
            "自由螺旋的形态是否连续、半径扩展是否稳定，线条是否抖动或出现明显空间失控。"
        case .sentenceCopying:
            "是否存在帕金森小写症线索，例如字高逐步变小、拥挤、笔画变短或基线漂移。"
        case .waveTracing:
            "波浪线描摹是否跟随模板，振幅和相位是否稳定，线条是否抖动。"
        case .circleTracing:
            "圆形闭合、半径稳定性、是否偏离模板以及线条抖动。"
        case .clockCommand, .clockCopy:
            "钟表外形、数字/刻度完整性和顺序、空间分布，以及指针是否表达 11 点 10 分。"
        case .holdRight, .holdLeft:
            "静止保持轨迹是否集中在中心目标附近，是否出现明显漂移或抖动。"
        case .tappingRight, .tappingLeft:
            "若图片存在，仅辅助检查触点分布；主要判断应基于结构化点击数据。"
        }
    }

    private func featureLines(_ features: TaskFeatureSet?) -> String {
        guard let features else { return "无特征数据。" }
        let values = featureHighlights(features)
        guard !values.isEmpty else { return "无特征数据。" }
        return values.keys.sorted().map { key in
            "\(key): \(String(format: "%.5g", values[key] ?? 0))"
        }.joined(separator: "\n")
    }

    private func makeSummary(
        score: Double?,
        taskCount: Int,
        overallResult: LargeModelAnalysisResult?
    ) -> String {
        guard let score else {
            return "未能生成有效研究关注分数，请检查本地模型资源和大模型配置。"
        }
        if let overallResult, overallResult.errorMessage == nil {
            return "已完成 \(taskCount) 项任务分析，最终研究关注分数由大模型 overall 综合分析给出：\(String(format: "%.0f", score))/100，等级：\(RiskLevel.from(score: score).rawValue)。\(overallResult.summary)"
        }
        return "已完成 \(taskCount) 项任务分析，综合研究关注分数 \(String(format: "%.0f", score))/100，等级：\(RiskLevel.from(score: score).rawValue)。"
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private struct SessionAnalysisSnapshot: Sendable {
    let completedTasks: [AnalysisTaskSnapshot]

    @MainActor
    init(session: TestSession) {
        completedTasks = session.orderedTasks
            .filter { $0.state == .completed }
            .map {
                AnalysisTaskSnapshot(
                    id: $0.id,
                    kind: $0.taskKind,
                    samplesRelativePath: $0.samplesRelativePath,
                    tapsRelativePath: $0.tapsRelativePath,
                    previewRelativePath: $0.previewRelativePath,
                    features: $0.features,
                    qualityFlags: $0.qualityFlags
                )
            }
    }
}

private struct AnalysisTaskSnapshot: Sendable {
    let id: UUID
    let kind: ResearchTaskKind
    let samplesRelativePath: String?
    let tapsRelativePath: String?
    let previewRelativePath: String?
    let features: TaskFeatureSet?
    let qualityFlags: [String]
}

private struct AnalysisTaskInput {
    let task: AnalysisTaskSnapshot
    let definition: ResearchTaskDefinition
    let samples: [PencilSample]
    let taps: [TapEvent]
    let previewURL: URL?
    let features: TaskFeatureSet?
}
