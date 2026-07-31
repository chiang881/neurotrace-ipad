import SwiftUI

struct MoreView: View {
    @AppStorage(LargeModelSettingsKeys.enabled) private var largeModelEnabled = false
    @AppStorage(LargeModelSettingsKeys.endpoint) private var endpoint = LargeModelConfiguration.defaultEndpoint
    @AppStorage(LargeModelSettingsKeys.apiKey) private var apiKey = ""
    @AppStorage(LargeModelSettingsKeys.model) private var model = LargeModelConfiguration.defaultModel
    @State private var isTestingModel = false
    @State private var isRequestingModels = false
    @State private var diagnosticMessage: String?
    @State private var modelIDs: [String] = []

    private var configurationIsReady: Bool {
        currentConfiguration.isReady
    }

    private var endpointIsValid: Bool {
        currentConfiguration.endpointURL != nil
    }

    private var currentConfiguration: LargeModelConfiguration {
        LargeModelConfiguration(
            isEnabled: largeModelEnabled,
            endpoint: endpoint,
            apiKey: apiKey,
            model: model
        )
    }

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle(
                        title: "更多",
                        subtitle: "模型配置、研究说明与本地分析设置"
                    )

                    SectionTitle("大模型配置")
                    GlassCard(tint: .purple.opacity(0.08)) {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("启用测试结束后的大模型分析", isOn: $largeModelEnabled)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .tint(.purple)

                            VStack(alignment: .leading, spacing: 7) {
                                Text("API 地址")
                                    .foregroundStyle(.white.opacity(0.68))
                                TextField("https://api.openai.com/v1/chat/completions", text: $endpoint)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Text("使用 OpenAI-compatible 地址；可填完整 /v1/chat/completions，也可填基础 /v1，程序会自动补全。HTTPS 可直接使用，HTTP 本地服务需要为具体 host 配置 App Transport Security 例外。")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.52))
                                if !endpointIsValid {
                                    Text("请输入完整 URL。")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                Text("模型名")
                                    .foregroundStyle(.white.opacity(0.68))
                                TextField("gpt-4o-mini", text: $model)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                Text("API Key（可选）")
                                    .foregroundStyle(.white.opacity(0.68))
                                SecureField("需要鉴权时填写；本地兼容服务可留空", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }

                            HStack {
                                StatusPill(
                                    text: configurationIsReady ? "配置完整" : "未配置完整",
                                    color: configurationIsReady ? .mint : .orange
                                )
                                Spacer()
                                Button {
                                    Task { await testModelOutput() }
                                } label: {
                                    if isTestingModel {
                                        ProgressView()
                                            .frame(width: 128, height: 38)
                                    } else {
                                        Label("测试输出", systemImage: "paperplane")
                                            .frame(width: 128, height: 38)
                                    }
                                }
                                .buttonStyle(.glass)
                                .disabled(!configurationIsReady || isTestingModel || isRequestingModels)

                                Button {
                                    Task { await requestModelList() }
                                } label: {
                                    if isRequestingModels {
                                        ProgressView()
                                            .frame(width: 138, height: 38)
                                    } else {
                                        Label("模型列表", systemImage: "list.bullet.rectangle")
                                            .frame(width: 138, height: 38)
                                    }
                                }
                                .buttonStyle(.glass)
                                .disabled(!configurationIsReady || isTestingModel || isRequestingModels)

                                Button("恢复默认地址") {
                                    endpoint = LargeModelConfiguration.defaultEndpoint
                                    model = LargeModelConfiguration.defaultModel
                                }
                                .buttonStyle(.glass)
                            }

                            if let diagnosticMessage {
                                Text(diagnosticMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .parchmentGlass(cornerRadius: 14, tint: .white.opacity(0.04), interactive: false)
                            }

                            if !modelIDs.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("模型列表（点击可填入模型名）")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white.opacity(0.68))
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                                        ForEach(modelIDs.prefix(40), id: \.self) { modelID in
                                            Button {
                                                model = modelID
                                            } label: {
                                                Text(modelID)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                    .frame(maxWidth: .infinity, minHeight: 34)
                                            }
                                            .buttonStyle(.glass)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionTitle("分析说明")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("本地模型：螺旋与压力 Core ML 模型均需要静态、动态螺旋配对输入；快速模式不含静态螺旋，因此不执行本地模型推理。", systemImage: "cpu")
                            Label("大模型：测试结束后会把已有预览图逐项发送到配置的 API；触屏敲击会发送结构化特征。", systemImage: "photo.on.rectangle.angled")
                            Label("报告：记录每项模型结果；最终研究关注分数优先由大模型 overall 综合分析给出，可随 ZIP 一起导出。", systemImage: "doc.text.magnifyingglass")
                            Label("所有输出均为研究辅助信息，不作为医学诊断。", systemImage: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
    }

    private func testModelOutput() async {
        isTestingModel = true
        defer { isTestingModel = false }
        diagnosticMessage = "正在请求测试输出…"
        do {
            let output = try await LargeModelClient(configuration: currentConfiguration)
                .testConnection()
            diagnosticMessage = "测试成功：\(output)"
        } catch {
            diagnosticMessage = "测试失败：\(describe(error))"
        }
    }

    private func requestModelList() async {
        isRequestingModels = true
        defer { isRequestingModels = false }
        diagnosticMessage = "正在请求模型列表…"
        do {
            let ids = try await LargeModelClient(configuration: currentConfiguration)
                .listModels()
            modelIDs = ids
            diagnosticMessage = ids.isEmpty
                ? "请求成功，但服务没有返回模型。"
                : "请求成功：共 \(ids.count) 个模型。"
        } catch {
            modelIDs = []
            diagnosticMessage = "模型列表请求失败：\(describe(error))"
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
