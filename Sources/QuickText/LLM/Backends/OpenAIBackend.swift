import Foundation

/// Calls the OpenAI Chat Completions API, or any server that speaks it (Ollama, LM Studio, DeepSeek…).
struct OpenAIBackend: LLMBackend {
    let configuration: ProviderConfiguration
    /// Replaced in tests to stub the network.
    var makeSessionConfiguration: @Sendable () -> URLSessionConfiguration = { .ephemeral }

    struct Request: Encodable, Equatable {
        struct Message: Encodable, Equatable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        /// Omitted unless chosen, so models and servers without reasoning still work.
        let reasoningEffort: String?
    }

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    static func request(system: String, user: String, model: String, effort: String?) -> Request {
        var messages: [Request.Message] = []
        if !system.isEmpty {
            messages.append(.init(role: "system", content: system))
        }
        messages.append(.init(role: "user", content: user))
        return Request(model: model, messages: messages, reasoningEffort: effort)
    }

    /// Only OpenAI itself requires a key; local servers usually don't.
    static func requiresAPIKey(_ baseURL: URL) -> Bool {
        baseURL.host?.lowercased() == "api.openai.com"
    }

    func complete(system: String, user: String) async throws -> String {
        guard let baseURL = configuration.baseURL ?? Provider.openAI.defaultBaseURL else {
            throw LLMError.requestFailed(.openAI, status: 0, message: "Invalid base URL.")
        }
        let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty && Self.requiresAPIKey(baseURL) {
            throw LLMError.missingAPIKey(.openAI)
        }

        let body = Self.request(system: system, user: user, model: configuration.model, effort: configuration.effort)
        let headers = key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
        let response = try await HTTPTransport.post(
            baseURL.appendingPathComponent("chat/completions"), headers: headers, body: body,
            provider: .openAI, timeout: configuration.timeout, sessionConfiguration: makeSessionConfiguration()
        )
        guard response.isSuccess else { throw HTTPTransport.error(for: response, provider: .openAI) }

        let completion = try HTTPTransport.decode(Response.self, from: response, provider: .openAI)
        guard let message = completion.choices.first?.message else { return "" }
        if let refusal = message.refusal, !refusal.isEmpty, (message.content ?? "").isEmpty {
            throw LLMError.refused(.openAI)
        }
        return message.content ?? ""
    }
}
