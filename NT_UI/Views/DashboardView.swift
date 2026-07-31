import SwiftData
import SwiftUI

struct DashboardView: View {
    @Binding var selectedTab: AppTab
    @Environment(AppServices.self) private var services
    @Query(sort: \Subject.updatedAt, order: .reverse) private var subjects: [Subject]
    @Query(sort: \TestSession.updatedAt, order: .reverse) private var sessions: [TestSession]

    private var activeSession: TestSession? {
        sessions.first { $0.state == .ready || $0.state == .inProgress }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(
                    title: "羊皮纸",
                    subtitle: "神经行为数据采集工具 · 仅用于研究数据采集，不提供医学诊断"
                )

                HStack(spacing: 16) {
                    subjectCard
                    pencilCard
                }

                if let activeSession {
                    activeSessionCard(activeSession)
                } else {
                    startCard
                }

                SectionTitle("快捷入口")
                HStack(spacing: 16) {
                    NavigationLink {
                        SubjectsView()
                    } label: {
                        actionCard(
                            symbol: "person.2.fill",
                            title: "受试者管理",
                            subtitle: "\(subjects.count) 位受试者",
                            tint: .mint
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = .records
                    } label: {
                        actionCard(
                            symbol: "square.and.arrow.up",
                            title: "数据导出",
                            subtitle: "\(sessions.count { $0.state == .completed }) 次已完成测试",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = .trends
                    } label: {
                        actionCard(
                            symbol: "chart.xyaxis.line",
                            title: "真实趋势",
                            subtitle: "仅基于已完成数据",
                            tint: .purple
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .appScreenPadding()
        }
        .scrollIndicators(.hidden)
        .navigationBarHidden(true)
    }

    private var subjectCard: some View {
        GlassCard(tint: .cyan.opacity(0.08)) {
            HStack(spacing: 18) {
                GlassIcon(symbol: "person.text.rectangle", tint: .cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("受试者")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(subjects.first?.code ?? "尚未建立受试者")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(subjects.first.map { "最近更新于 \($0.updatedAt.formatted(date: .abbreviated, time: .shortened))" } ?? "请先录入研究编号")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }
        }
    }

    private var pencilCard: some View {
        GlassCard(tint: (services.pencilMonitor.hasDetectedPencil ? Color.mint : .orange).opacity(0.08)) {
            HStack(spacing: 18) {
                GlassIcon(
                    symbol: services.pencilMonitor.hasDetectedPencil ? "pencil.tip.crop.circle.badge.checkmark" : "pencil.tip.crop.circle",
                    tint: services.pencilMonitor.hasDetectedPencil ? .mint : .orange
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple Pencil")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(services.pencilMonitor.statusText)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("系统不提供蓝牙连接或电量查询")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }
        }
    }

    private var startCard: some View {
        GlassCard(tint: .blue.opacity(0.10)) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("准备开始一次真实采集")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subjects.isEmpty ? "建立受试者后即可创建测试。" : "选择受试者与测试模式，任务会按固定顺序进行。")
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Button {
                    selectedTab = .collection
                } label: {
                    Label("开始新测试", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 190, height: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
            }
        }
    }

    private func activeSessionCard(_ session: TestSession) -> some View {
        GlassCard(tint: .mint.opacity(0.10)) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("未完成测试")
                            .font(.caption.bold())
                            .foregroundStyle(.mint)
                        StatusPill(text: session.state.title, color: .mint)
                    }
                    Text(session.displayName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(activeSessionSubtitle(session))
                        .foregroundStyle(.white.opacity(0.68))
                    ProgressView(value: session.progress)
                        .tint(.mint)
                        .frame(maxWidth: 480)
                }
                Spacer()
                Button {
                    selectedTab = .collection
                } label: {
                    Label("继续测试", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(width: 180, height: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.mint)
                .accessibilityIdentifier("continue.session")
            }
        }
    }

    private func activeSessionSubtitle(_ session: TestSession) -> String {
        var components: [String] = []
        if session.hasCustomName {
            components.append(session.subject?.code ?? "未知受试者")
        }
        components.append("\(session.completedTaskCount) / \(session.tasks.count) 项已完成")
        components.append(session.mode.rawValue)
        return components.joined(separator: " · ")
    }

    private func actionCard(symbol: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 16) {
            GlassIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104)
        .parchmentGlass(cornerRadius: 24, tint: tint.opacity(0.07), interactive: true)
    }
}
