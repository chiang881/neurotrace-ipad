import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TestSession.updatedAt, order: .reverse) private var sessions: [TestSession]

    @State private var shareItem: ShareItem?
    @State private var sessionPendingDeletion: TestSession?
    @State private var exportingSessionID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle(
                        title: "测试记录",
                        subtitle: "查看真实会话、任务预览、特征数据与本地 ZIP 导出"
                    )

                    if sessions.isEmpty {
                        EmptyStateView(
                            symbol: "doc.text.magnifyingglass",
                            title: "暂无测试记录",
                            message: "完成或创建测试后，记录会自动出现在这里。"
                        )
                    } else {
                        ForEach(sessions) { session in
                            HStack(spacing: 12) {
                                NavigationLink {
                                    SessionDetailView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)

                                VStack(spacing: 10) {
                                    Button {
                                        Task { await export(session) }
                                    } label: {
                                        if exportingSessionID == session.id {
                                            ProgressView()
                                                .frame(width: 48, height: 48)
                                        } else {
                                            Image(systemName: "square.and.arrow.up")
                                                .frame(width: 48, height: 48)
                                        }
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(session.state != .completed || exportingSessionID != nil)

                                    Button(role: .destructive) {
                                        sessionPendingDeletion = session
                                    } label: {
                                        Image(systemName: "trash")
                                            .frame(width: 48, height: 48)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert("删除本次测试？", isPresented: Binding(
            get: { sessionPendingDeletion != nil },
            set: { if !$0 { sessionPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let session = sessionPendingDeletion else { return }
                Task { await delete(session) }
            }
        } message: {
            Text("原始点、点击事件、预览图和特征数据会一并删除。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export(_ session: TestSession) async {
        exportingSessionID = session.id
        defer { exportingSessionID = nil }
        do {
            shareItem = ShareItem(url: try await services.exportService.export(session: session))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ session: TestSession) async {
        do {
            try await services.delete(session: session, context: modelContext)
            sessionPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
