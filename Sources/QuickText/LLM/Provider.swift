import Foundation

/// Where requests go.
enum Provider: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case anthropic
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .anthropic: return "Anthropic API"
        case .openAI: return "OpenAI API"
        }
    }

    /// Runs a locally installed command-line tool rather than calling an HTTP API.
    var isCommandLineTool: Bool {
        self == .claudeCode || self == .codex
    }

    /// The command-line tool's executable name.
    var executableName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .anthropic, .openAI: return nil
        }
    }

    /// Empty means "let the tool choose".
    var defaultModel: String {
        switch self {
        case .claudeCode: return "sonnet"
        case .codex: return ""
        case .anthropic: return "claude-sonnet-5-5"
        case .openAI: return "gpt-6.1-terra"
        }
    }

    /// Reasoning effort levels the provider accepts.
    var efforts: [String] {
        switch self {
        case .claudeCode, .anthropic: return ["low", "medium", "high", "xhigh", "max"]
        case .codex: return ["minimal", "low", "medium", "high", "xhigh"]
        case .openAI: return ["none", "low", "medium", "high", "xhigh", "max"]
        }
    }

    /// nil means the parameter is not sent, so the model's own default applies.
    var defaultEffort: String? {
        switch self {
        case .claudeCode, .codex, .anthropic: return "low"
        case .openAI: return nil
        }
    }

    var defaultBaseURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com")
        case .openAI: return URL(string: "https://api.openai.com/v1")
        case .claudeCode, .codex: return nil
        }
    }

    /// Who the user is talking to, for error messages.
    var serviceName: String {
        switch self {
        case .claudeCode, .anthropic: return "Claude"
        case .codex: return "Codex"
        case .openAI: return "OpenAI"
        }
    }
}

/// Everything one request needs, read fresh from Settings each time.
struct ProviderConfiguration: Equatable, Sendable {
    var provider: Provider
    /// Empty means the provider's own default (only meaningful for Codex).
    var model: String
    /// nil means not sent.
    var effort: String?
    var timeout: TimeInterval = 30
    /// Command-line tools: a manually chosen executable; nil means auto-detect.
    var executablePath: String?
    /// HTTP APIs.
    var apiKey: String?
    var baseURL: URL?

    init(provider: Provider, model: String? = nil, effort: String? = nil, timeout: TimeInterval = 30,
         executablePath: String? = nil, apiKey: String? = nil, baseURL: URL? = nil) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.effort = effort
        self.timeout = timeout
        self.executablePath = executablePath
        self.apiKey = apiKey
        self.baseURL = baseURL ?? provider.defaultBaseURL
    }
}

/// Sends each request to whichever provider is selected in Settings at that moment.
struct ProviderBackend: LLMBackend {
    let configuration: @Sendable () -> ProviderConfiguration

    func complete(system: String, user: String) async throws -> String {
        try await Self.backend(for: configuration()).complete(system: system, user: user)
    }

    static func backend(for configuration: ProviderConfiguration) -> LLMBackend {
        switch configuration.provider {
        case .claudeCode: return ClaudeCodeBackend(configuration: configuration)
        case .codex: return CodexBackend(configuration: configuration)
        case .anthropic: return AnthropicBackend(configuration: configuration)
        case .openAI: return OpenAIBackend(configuration: configuration)
        }
    }
}
