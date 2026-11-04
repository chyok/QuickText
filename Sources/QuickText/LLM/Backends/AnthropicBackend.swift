import Foundation

/// Calls the Claude Messages API directly with an API key.
struct AnthropicBackend: LLMBackend {
    static let apiVersion = "2026-10-21"
    static let maxTokens = 16_000
    /// Lets the API retry a declined request on the model Anthropic recommends for that case.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let modelsWithServerFallback: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    let configuration: ProviderConfiguration
    /// Replaced in tests to stub the network.
    var makeSessionConfiguration: @Sendable () -> URLSessionConfiguration = { .ephemeral }

    struct Request: Encodable, Equatable {
        struct Message: Encodable, Equatable {
            let role: String
            let content: String
        }

        struct OutputConfig: Encodable, Equatable {
            let effort: String
        }

        let model: String
        let maxTokens: Int
        /// Omitted for Send, which has no prompt.
        let system: String?
        let messages: [Message]
        let outputConfig: OutputConfig?
        let fallbacks: String?
    }

    struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?
    }

    static func request(system: String, user: String, model: String, effort: String?) -> Request {
        Request(
            model: model,
            maxTokens: maxTokens,
            system: system.isEmpty ? nil : system,
            messages: [.init(role: "user", content: user)],
            outputConfig: effort.map(Request.OutputConfig.init(effort:)),
            fallbacks: modelsWithServerFallback.contains(model) ? "default" : nil
        )
    }

    func complete(system: String, user: String) async throws -> String {
        let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw LLMError.missingAPIKey(.anthropic) }
        guard let baseURL = configuration.baseURL ?? Provider.anthropic.defaultBaseURL else {
            throw LLMError.requestFailed(.anthropic, status: 0, message: "Invalid base URL.")
        }

        let body = Self.request(system: system, user: user, model: configuration.model, effort: configuration.effort)
        var headers = ["x-api-key": key, "anthropic-version": Self.apiVersion]
        if body.fallbacks != nil {
            headers["anthropic-beta"] = Self.fallbackBeta
        }

        let response = try await HTTPTransport.post(
            baseURL.appendingPathComponent("v1/messages"), headers: headers, body: body,
            provider: .anthropic, timeout: configuration.timeout, sessionConfiguration: makeSessionConfiguration()
        )
        guard response.isSuccess else { throw HTTPTransport.error(for: response, provider: .anthropic) }

        let message = try HTTPTransport.decode(Response.self, from: response, provider: .anthropic)
        if message.stopReason == "refusal" {
            throw LLMError.refused(.anthropic)
        }
        // Thinking and other blocks are skipped; only the visible answer counts.
        return message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }
}
