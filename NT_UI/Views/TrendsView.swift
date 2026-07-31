import SwiftData
import SwiftUI

struct TrendsView: View {
    @Query(sort: \TestSession.completedAt, order: .forward) private var sessions: [TestSession]

    private var completedSessions: [TestSession] {
        sessions.filter { $0.state == .completed }
    }

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle(
                        title: "数据趋势",
                        subtitle: "仅呈现已完成测试的测量值，不生成医学判断"
                    )

                    if completedSessions.isEmpty {
                        EmptyStateView(
                            symbol: "chart.xyaxis.line",
                            title: "暂无可用趋势",
                            message: "至少完成一次测试后才会显示真实数据。"
                        )
                    } else {
                        summaryCards
                        metricSection(
                            title: "平均标准化压力",
                            key: "forceMean",
                            tint: .blue
                        )
                        metricSection(
                            title: "3–8 Hz 轨迹能量",
                            key: "tremorPower3to8Hz",
                            tint: .mint
                        )
                        metricSection(
                            title: "平均速度",
                            key: "avgSpeed",
                            tint: .purple
                        )
                    }
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
    }

    private var summaryCards: some View {
        HStack(spacing: 14) {
            summaryCard(
                title: "已完成测试",
                value: "\(completedSessions.count)",
                symbol: "checkmark.seal.fill",
                tint: .mint
            )
            summaryCard(
                title: "受试者数量",
                value: "\(Set(completedSessions.compactMap { $0.subject?.id }).count)",
                symbol: "person.2.fill",
                tint: .cyan
            )
            summaryCard(
                title: "有效任务",
                value: "\(completedSessions.flatMap(\.tasks).count { $0.features != nil })",
                symbol: "waveform.path.ecg",
                tint: .purple
            )
        }
    }

    private func summaryCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        GlassCard(tint: tint.opacity(0.08)) {
            HStack {
                GlassIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(title)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
            }
        }
    }

    private func metricSection(title: String, key: String, tint: Color) -> some View {
        let points = completedSessions.compactMap { session -> TrendPoint? in
            let values = session.tasks.compactMap { $0.features?.values[key] }
            guard !values.isEmpty, let date = session.completedAt else { return nil }
            return TrendPoint(
                date: date,
                value: values.reduce(0, +) / Double(values.count),
                subjectCode: session.subject?.code ?? "未知"
            )
        }

        return GlassCard(tint: tint.opacity(0.07)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(points.count) 个会话")
                        .foregroundStyle(.white.opacity(0.56))
                }

                if points.isEmpty {
                    Text("现有会话没有此项特征。")
                        .frame(maxWidth: .infinity, minHeight: 130)
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    RealLineChart(points: points.map(\.value), tint: tint)
                        .frame(height: 150)
                    HStack {
                        Text(points.first?.date.formatted(date: .numeric, time: .omitted) ?? "")
                        Spacer()
                        Text(points.last?.date.formatted(date: .numeric, time: .omitted) ?? "")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
    }
}

private struct TrendPoint {
    let date: Date
    let value: Double
    let subjectCode: String
}

private struct RealLineChart: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let minValue = points.min() ?? 0
            let maxValue = points.max() ?? 1
            let span = max(0.000_001, maxValue - minValue)
            let step = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : 0

            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Path { path in
                        let y = proxy.size.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                Path { path in
                    for index in points.indices {
                        let normalized = (points[index] - minValue) / span
                        let point = CGPoint(
                            x: CGFloat(index) * step,
                            y: proxy.size.height * (1 - normalized)
                        )
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(
                    LinearGradient(colors: [tint, .cyan], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
