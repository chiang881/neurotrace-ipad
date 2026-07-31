import SwiftUI

struct AnalysisReportSummaryView: View {
    let report: SessionAnalysisReport

    var body: some View {
        GlassCard(tint: riskColor(report.overallRiskLevel).opacity(0.08)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    GlassIcon(symbol: "waveform.path.ecg.rectangle", tint: riskColor(report.overallRiskLevel))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("综合分析报告")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text(report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 7) {
                        Text(report.overallRiskScore.map { "\(Int($0.rounded()))" } ?? "--")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        StatusPill(text: report.overallRiskLevel.rawValue, color: riskColor(report.overallRiskLevel))
                    }
                }

                Text(report.summary)
                    .foregroundStyle(.white.opacity(0.76))

                if let result = report.overallLargeModelResult {
                    resultLine(
                        title: result.userFacingTitle,
                        summary: result.errorMessage ?? result.summary,
                        riskScore: result.riskScore
                    )
                    if !result.findings.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("overall 依据")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.70))
                            ForEach(result.findings.prefix(6), id: \.self) { finding in
                                Text("- \(finding)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.64))
                            }
                        }
                    }
                }

                if !report.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("注意事项")
                            .font(.headline)
                            .foregroundStyle(.white)
                        ForEach(report.warnings.prefix(4), id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.white.opacity(0.68))
                                .font(.subheadline)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("任务结果")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(report.taskReports) { taskReport in
                        taskReportRow(taskReport)
                    }
                }
            }
        }
    }

    private func taskReportRow(_ taskReport: TaskAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(taskReport.hand == "无" ? taskReport.title : "\(taskReport.title) · \(taskReport.hand)")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                StatusPill(text: taskReport.riskLevel.rawValue, color: riskColor(taskReport.riskLevel))
            }

            if let riskScore = taskReport.riskScore {
                Text("研究模式分数 \(Int(riskScore.rounded()))/100")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }

            ForEach(taskReport.localModelResults) { result in
                resultLine(
                    title: result.modelName,
                    summary: result.errorMessage ?? result.summary,
                    riskScore: result.riskScore
                )
            }

            ForEach(taskReport.largeModelResults) { result in
                resultLine(
                    title: result.userFacingTitle,
                    summary: result.errorMessage ?? result.summary,
                    riskScore: result.riskScore
                )
            }

            if taskReport.localModelResults.isEmpty, taskReport.largeModelResults.isEmpty {
                Text("本项暂无模型分析结果，仅保留特征数据。")
                    .foregroundStyle(.white.opacity(0.54))
                    .font(.subheadline)
            }
        }
        .padding(14)
        .parchmentGlass(cornerRadius: 18, tint: .white.opacity(0.04), interactive: false)
    }

    private func resultLine(title: String, summary: String, riskScore: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.70))
                Spacer()
                if let riskScore {
                    Text("\(Int(riskScore.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
        }
    }

    private func riskColor(_ level: RiskLevel) -> Color {
        switch level {
        case .low: .mint
        case .medium: .orange
        case .high: .red
        case .unknown: .gray
        }
    }
}
