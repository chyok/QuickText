import Foundation
import Testing
@testable import QuickText

private func anthropic(_ server: StubServer, key: String? = "sk-ant-test", model: String = "claude-sonnet-5-5",
                       effort: String? = "low") -> AnthropicBackend {
    var backend = AnthropicBackend(configuration: ProviderConfiguration(
        provider: .anthropic, model: model, effort: effort, apiKey: key,
        baseURL: URL(string: "https://\(server.host)")))
    backend.makeSessionConfiguration = { StubServer.sessionConfiguration() }
    return backend
}

private func openAI(_ server: StubServer, key: String? = "sk-test", baseURL: URL? = nil,
                    effort: String? = nil) -> OpenAIBackend {
    var backend = OpenAIBackend(configuration: ProviderConfiguration(
        provider: .openAI, model: "gpt-6.1-terra", effort: effort, apiKey: key, baseURL: baseURL ?? server.baseURL))
    backend.makeSessionConfiguration = { StubServer.sessionConfiguration() }
    return backend
}

private let anthropicAnswer = """
    {"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "Hello"}, {"type": "text", "text": " there"}],
     "stop_reason": "end_turn"}
    """

@Suite struct AnthropicBackendTests {
    @Test func requestShapeHeadersAndAnswer() async throws {
        let server = StubServer(.json(status: 200, anthropicAnswer))
        let output = try await anthropic(server).complete(system: "Be brief.", user: "hi 你好")
        #expect(output == "Hello there")

        let request = try #require(server.requests.last?.request)
        #expect(request.url?.path == "/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicBackend.apiVersion)
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == AnthropicBackend.fallbackBeta)

        let body = server.lastBody
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        #expect(body["max_tokens"] as? Int == AnthropicBackend.maxTokens)
        #expect(body["system"] as? String == "Be brief.")
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: String]) == ["effort": "low"])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "hi 你好"]])
    }

    @Test func sendWithoutPromptEffortOrFallback() async throws {
        let server = StubServer(.json(status: 200, anthropicAnswer))
        _ = try await anthropic(server, model: "claude-haiku-4-5", effort: nil).complete(system: "", user: "hi")
        let body = server.lastBody
        #expect(body["system"] == nil)
        #expect(body["output_config"] == nil)
        #expect(body["fallbacks"] == nil)
        #expect(server.requests.last?.request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func missingKeyFailsWithoutARequest() async {
        let server = StubServer(.json(status: 200, anthropicAnswer))
        await #expect(throws: LLMError.missingAPIKey(.anthropic)) {
            try await anthropic(server, key: "  ").complete(system: "", user: "hi")
        }
        #expect(server.requests.isEmpty)
    }

    @Test func refusalIsAnError() async {
        let server = StubServer(.json(status: 200, #"{"content": [], "stop_reason": "refusal"}"#))
        await #expect(throws: LLMError.refused(.anthropic)) {
            try await anthropic(server).complete(system: "", user: "hi")
        }
    }

    @Test func httpErrorsAreClassified() async {
        let cases: [(Int, String, LLMError)] = [
            (401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
             .credentialsRejected(.anthropic)),
            (429, #"{"error":{"message":"slow down"}}"#, .rateLimited(.anthropic)),
            (529, #"{"error":{"message":"Overloaded"}}"#, .overloaded(.anthropic)),
            (400, #"{"type":"error","error":{"type":"invalid_request_error","message":"model: not found"}}"#,
             .requestFailed(.anthropic, status: 400, message: "model: not found")),
        ]
        for (status, json, expected) in cases {
            let server = StubServer(.json(status: status, json))
            await #expect(throws: expected) {
                try await anthropic(server).complete(system: "", user: "hi")
            }
        }
    }

    @Test func networkFailures() async {
        await #expect(throws: LLMError.timeout) {
            try await anthropic(StubServer(.failure(.timedOut))).complete(system: "", user: "hi")
        }
        let offline = URLError(.notConnectedToInternet).localizedDescription
        await #expect(throws: LLMError.network(.anthropic, offline)) {
            try await anthropic(StubServer(.failure(.notConnectedToInternet))).complete(system: "", user: "hi")
        }
    }
}

@Suite struct OpenAIBackendTests {
    private let answer = #"{"choices": [{"message": {"role": "assistant", "content": "Bonjour", "refusal": null}}]}"#

    @Test func requestShapeHeadersAndAnswer() async throws {
        let server = StubServer(.json(status: 200, answer))
        let output = try await openAI(server, effort: "low").complete(system: "Translate.", user: "Hello")
        #expect(output == "Bonjour")

        let request = try #require(server.requests.last?.request)
        #expect(request.url?.path == "/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        let body = server.lastBody
        #expect(body["model"] as? String == "gpt-6.1-terra")
        #expect(body["reasoning_effort"] as? String == "low")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "Translate."], ["role": "user", "content": "Hello"]])
    }

    @Test func localServerNeedsNoKeyAndSendHasNoSystemMessage() async throws {
        let server = StubServer(.json(status: 200, answer))
        _ = try await openAI(server, key: nil).complete(system: "", user: "Hi")
        #expect(server.requests.last?.request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = server.lastBody
        #expect(body["reasoning_effort"] == nil)
        #expect((body["messages"] as? [[String: String]]) == [["role": "user", "content": "Hi"]])
    }

    @Test func openAIItselfRequiresAKey() async {
        let server = StubServer(.json(status: 200, answer))
        await #expect(throws: LLMError.missingAPIKey(.openAI)) {
            try await openAI(server, key: nil, baseURL: URL(string: "https://api.openai.com/v1"))
                .complete(system: "", user: "hi")
        }
    }

    @Test func refusalsAndErrors() async {
        let refusal = StubServer(.json(status: 200, #"{"choices": [{"message": {"content": null, "refusal": "No."}}]}"#))
        await #expect(throws: LLMError.refused(.openAI)) {
            try await openAI(refusal).complete(system: "", user: "hi")
        }
        let rejected = StubServer(.json(status: 401, #"{"error": {"message": "Incorrect API key"}}"#))
        await #expect(throws: LLMError.credentialsRejected(.openAI)) {
            try await openAI(rejected).complete(system: "", user: "hi")
        }
        let garbage = StubServer(.json(status: 200, "not json"))
        await #expect(throws: LLMError.requestFailed(.openAI, status: 200, message: "Unexpected response.")) {
            try await openAI(garbage).complete(system: "", user: "hi")
        }
    }
}
