import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .dashboard
    @State private var bootstrapError: String?

    var body: some View {
        ZStack {
            AppleGlassBackdrop()
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(selectedTab: $selectedTab)
                }
                .tabItem {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.symbol)
                        .accessibilityIdentifier("tab.dashboard")
                }
                .tag(AppTab.dashboard)

                NavigationStack {
                    CollectionRootView()
                }
                .tabItem {
                    Label(AppTab.collection.title, systemImage: AppTab.collection.symbol)
                        .accessibilityIdentifier("tab.collection")
                }
                .tag(AppTab.collection)

                NavigationStack {
                    RecordsView()
                }
                .tabItem {
                    Label(AppTab.records.title, systemImage: AppTab.records.symbol)
                        .accessibilityIdentifier("tab.records")
                }
                .tag(AppTab.records)

                NavigationStack {
                    TrendsView()
                }
                .tabItem {
                    Label(AppTab.trends.title, systemImage: AppTab.trends.symbol)
                        .accessibilityIdentifier("tab.trends")
                }
                .tag(AppTab.trends)

                NavigationStack {
                    MoreView()
                }
                .tabItem {
                    Label(AppTab.more.title, systemImage: AppTab.more.symbol)
                        .accessibilityIdentifier("tab.more")
                }
                .tag(AppTab.more)
            }
            .tint(.cyan)
            .toolbarColorScheme(.dark, for: .tabBar)
        }
        .preferredColorScheme(.dark)
        .task {
            do {
                try seedUITestSessionIfRequested()
                try services.recoverInterruptedTasks(context: modelContext)
            } catch {
                bootstrapError = error.localizedDescription
            }
        }
        .alert("数据恢复失败", isPresented: Binding(
            get: { bootstrapError != nil },
            set: { if !$0 { bootstrapError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(bootstrapError ?? "")
        }
    }

    private func seedUITestSessionIfRequested() throws {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let shouldSeedActiveSession = arguments.contains("-uiTestSeedActiveSession")
        let shouldSeedInterruptedSession = arguments.contains("-uiTestSeedInterruptedSession")
        guard shouldSeedActiveSession || shouldSeedInterruptedSession else { return }

        for subject in try modelContext.fetch(FetchDescriptor<Subject>()) {
            modelContext.delete(subject)
        }
        try modelContext.save()

        let subject = Subject(code: "S-UI-001")
        modelContext.insert(subject)
        let session = try services.createSession(subject: subject, mode: .quick, context: modelContext)
        if shouldSeedInterruptedSession, let firstTask = session.orderedTasks.first {
            firstTask.state = .inProgress
            session.state = .inProgress
            session.startedAt = .now
            try modelContext.save()
        }
        #endif
    }
}

enum AppTab: Hashable {
    case dashboard
    case collection
    case records
    case trends
    case more

    var title: String {
        switch self {
        case .dashboard: "概览"
        case .collection: "采集"
        case .records: "记录"
        case .trends: "趋势"
        case .more: "更多"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2.fill"
        case .collection: "pencil.tip.crop.circle"
        case .records: "doc.text"
        case .trends: "chart.xyaxis.line"
        case .more: "ellipsis.circle.fill"
        }
    }
}
