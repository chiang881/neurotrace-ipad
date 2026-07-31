import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum LargeModelSettingsKeys {
    static let enabled = "largeModel.enabled"
    static let endpoint = "largeModel.endpoint"
    static let apiKey = "largeModel.apiKey"
    static let model = "largeModel.model"
}

nonisolated struct LargeModelConfiguration {
    var isEnabled: Bool
    var endpoint: String
    var apiKey: String
    var model: String

    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultModel = "gpt-4o-mini"

    static func load(defaults: UserDefaults = .standard) -> LargeModelConfiguration {
        LargeModelConfiguration(
            isEnabled: defaults.bool(forKey: LargeModelSettingsKeys.enabled),
            endpoint: defaults.string(forKey: LargeModelSettingsKeys.endpoint) ?? defaultEndpoint,
            apiKey: defaults.string(forKey: LargeModelSettingsKeys.apiKey) ?? "",
            model: defaults.string(forKey: LargeModelSettingsKeys.model) ?? defaultModel
        )
    }

    var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var endpointURL: URL? {
        guard
            let components = URLComponents(string: trimmedEndpoint),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host,
            !host.isEmpty
        else { return nil }
        return components.url
    }

    var isReady: Bool {
        isEnabled
            && endpointURL != nil
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated struct LargeModelParsedResponse {
    let summary: String
    let findings: [String]
    let riskScore: Double?
    let rawText: String
}

nonisolated enum LargeModelClientError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case emptyResponse
    case httpStatus(Int, String)
    case unrecognizedModelList(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "大模型 API 未启用或配置不完整。"
        case .invalidEndpoint: "大模型 API 地址无效。"
        case .emptyResponse: "大模型 API 返回为空。"
        case .httpStatus(let status, let body): "大模型 API 请求失败（HTTP \(status)）：\(body)"
        case .unrecognizedModelList(let body): "无法解析模型列表返回：\(body)"
        case .transport(let message): "大模型 API 网络请求失败：\(message)"
        }
    }
}

nonisolated struct LargeModelClient {
    private let configuration: LargeModelConfiguration
    private let session: URLSession

    init(
        configuration: LargeModelConfiguration = .load(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func analyzeImage(
        pngData: Data,
        prompt: String
    ) async throws -> LargeModelParsedResponse {
        let payload = Self.optimizedImagePayload(from: pngData)
        return try await request(
            parts: [
                .text(prompt),
                .imageURL("data:\(payload.mimeType);base64,\(payload.data.base64EncodedString())")
            ]
        )
    }

    func analyzeText(prompt: String) async throws -> LargeModelParsedResponse {
        try await request(parts: [.text(prompt)])
    }

    func testConnection() async throws -> String {
        try await requestRaw(
            parts: [.text("请只回复：连接成功")],
            systemPrompt: "你是接口连通性测试助手。请严格按用户要求回复。",
            timeoutInterval: 20
        )
    }

    func listModels() async throws -> [String] {
        guard configuration.isReady else { throw LargeModelClientError.notConfigured }
        var request = URLRequest(url: try resolvedModelsEndpointURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await perform(request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LargeModelClientError.httpStatus(httpResponse.statusCode, body)
        }

        if let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data),
           let data = decoded.data {
            return data.map(\.id).sorted()
        }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded.sorted()
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw LargeModelClientError.unrecognizedModelList(body)
    }

    private func request(parts: [ChatContentPart]) async throws -> LargeModelParsedResponse {
        parse(try await requestRaw(parts: parts))
    }

    private func requestRaw(
        parts: [ChatContentPart],
        systemPrompt: String = """
        你是神经行为研究数据分析助手。只能基于给定图像或特征做研究性观察，不给医学诊断、治疗建议或确定性结论。请输出 JSON。
        """,
        timeoutInterval: TimeInterval = 45
    ) async throws -> String {
        guard configuration.isReady else { throw LargeModelClientError.notConfigured }
        let url = try resolvedChatCompletionsEndpointURL()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: configuration.model,
            messages: [
                .init(
                    role: "system",
                    content: [.text(systemPrompt)]
                ),
                .init(role: "user", content: parts)
            ],
            temperature: 0.1
        ))

        let (data, response) = try await perform(request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LargeModelClientError.httpStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let rawText = decoded.choices.first?.message.content,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LargeModelClientError.emptyResponse
        }
        return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedChatCompletionsEndpointURL() throws -> URL {
        guard var url = configuration.endpointURL else {
            throw LargeModelClientError.invalidEndpoint
        }
        if url.lastPathComponent == "completions",
           url.deletingLastPathComponent().lastPathComponent == "chat" {
            return url
        }
        if url.lastPathComponent == "models" || url.lastPathComponent == "responses" {
            url = url.deletingLastPathComponent()
        }
        return url.appending(path: "chat").appending(path: "completions")
    }

    func resolvedModelsEndpointURL() throws -> URL {
        guard var url = configuration.endpointURL else {
            throw LargeModelClientError.invalidEndpoint
        }
        if url.lastPathComponent == "models" {
            return url
        }
        if url.lastPathComponent == "completions",
           url.deletingLastPathComponent().lastPathComponent == "chat" {
            url = url.deletingLastPathComponent().deletingLastPathComponent()
            return url.appending(path: "models")
        }
        if url.lastPathComponent == "responses" {
            return url.deletingLastPathComponent().appending(path: "models")
        }
        return url.appending(path: "models")
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            let url = request.url?.absoluteString ?? "未知地址"
            if error.code == .timedOut {
                throw LargeModelClientError.transport("请求超时（\(url)）。请确认地址是否为 OpenAI-compatible 服务，基础地址应能推导到 /v1/chat/completions。")
            }
            throw LargeModelClientError.transport("\(url)：\(error.localizedDescription)")
        } catch {
            throw LargeModelClientError.transport(error.localizedDescription)
        }
    }

    private static func optimizedImagePayload(from data: Data) -> (mimeType: String, data: Data) {
        let fallback = (mimeType: "image/png", data: data)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 900
                ] as CFDictionary
            )
        else {
            return fallback
        }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return fallback
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.74] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return fallback
        }
        let optimized = output as Data
        return optimized.count < data.count
            ? (mimeType: "image/jpeg", data: optimized)
            : fallback
    }

    private func parse(_ rawText: String) -> LargeModelParsedResponse {
        if
            let json = extractJSONObject(from: rawText),
            let data = json.data(using: .utf8),
            let structured = try? JSONDecoder().decode(StructuredLargeModelResponse.self, from: data)
        {
            return LargeModelParsedResponse(
                summary: structured.summary,
                findings: structured.findings ?? [],
                riskScore: structured.riskScore.map { min(max($0, 0), 100) },
                rawText: rawText
            )
        }

        return LargeModelParsedResponse(
            summary: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            findings: [],
            riskScore: nil,
            rawText: rawText
        )
    }

    private func extractJSONObject(from text: String) -> String? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start <= end
        else { return nil }
        return String(text[start...end])
    }
}

nonisolated private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

nonisolated private struct ChatMessage: Encodable {
    let role: String
    let content: [ChatContentPart]
}

nonisolated private enum ChatContentPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

nonisolated private struct ImageURL: Encodable {
    let url: String
}

nonisolated private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

nonisolated private struct ModelListResponse: Decodable {
    let data: [ModelInfo]?

    struct ModelInfo: Decodable {
        let id: String
    }
}

nonisolated private struct StructuredLargeModelResponse: Decodable {
    let summary: String
    let findings: [String]?
    let riskScore: Double?

    private enum CodingKeys: String, CodingKey {
        case summary
        case findings
        case riskScore = "risk_score"
    }
}
