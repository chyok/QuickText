import Foundation
import Testing
@testable import QuickText

@Suite struct SettingsTests {
    @Test func defaultsForEveryProvider() {
        let temporary = TemporaryDefaults()
        let secrets = InMemorySecretStore()

        let claude = Settings.configuration(defaults: temporary.defaults, secrets: secrets)
        #expect(claude == ProviderConfiguration(provider: .claudeCode, model: "sonnet", effort: "low", timeout: 30))

        let codex = Settings.configuration(for: .codex, defaults: temporary.defaults, secrets: secrets)
        #expect(codex.model == "")
        #expect(codex.effort == "low")

        let anthropic = Settings.configuration(for: .anthropic, defaults: temporary.defaults, secrets: secrets)
        #expect(anthropic.model == "claude-sonnet-5-5")
        #expect(anthropic.apiKey == nil)
        #expect(anthropic.baseURL == URL(string: "https://api.anthropic.com"))

        let openAI = Settings.configuration(for: .openAI, defaults: temporary.defaults, secrets: secrets)
        #expect(openAI.model == "gpt-6.1-terra")
        #expect(openAI.effort == nil)
        #expect(openAI.baseURL == URL(string: "https://api.openai.com/v1"))
    }

    @Test func eachProviderKeepsItsOwnFields() {
        let temporary = TemporaryDefaults()
        let secrets = InMemorySecretStore()
        let settings = Settings(defaults: temporary.defaults, secrets: secrets)

        settings.model = "haiku"
        settings.effort = "high"
        settings.provider = .anthropic
        #expect(settings.model == "")
        #expect(settings.effort == "low")
        settings.apiKey = " sk-ant-123 \n"
        settings.model = "claude-opus-5-5"
        settings.provider = .claudeCode
        #expect(settings.model == "haiku")
        #expect(settings.effort == "high")
        #expect(settings.apiKey == "")

        // Switching providers only reads the Keychain; it never writes to it.
        #expect(secrets.writeCount == 1)
        #expect(secrets.read("anthropic") == "sk-ant-123")

        let anthropic = Settings.configuration(for: .anthropic, defaults: temporary.defaults, secrets: secrets)
        #expect(anthropic.apiKey == "sk-ant-123")
        #expect(anthropic.model == "claude-opus-5-5")
        #expect(Settings.configuration(defaults: temporary.defaults, secrets: secrets).provider == .claudeCode)
    }

    @Test func openAIBaseURLAndModelDefaultEffort() {
        let temporary = TemporaryDefaults()
        let settings = Settings(defaults: temporary.defaults, secrets: InMemorySecretStore())
        settings.provider = .openAI
        #expect(settings.effort == "")
        settings.baseURL = "http://localhost:11434/v1"
        settings.model = "  llama4  "

        let openAI = Settings.configuration(defaults: temporary.defaults, secrets: InMemorySecretStore())
        #expect(openAI.provider == .openAI)
        #expect(openAI.baseURL == URL(string: "http://localhost:11434/v1"))
        #expect(openAI.model == "llama4")
        #expect(openAI.effort == nil)

        settings.baseURL = "localhost:11434"
        #expect(Settings.configuration(defaults: temporary.defaults, secrets: InMemorySecretStore()).baseURL
                == Provider.openAI.defaultBaseURL)
    }

    @Test func effortAndTimeoutValidation() {
        #expect(Settings.resolvedEffort(nil, for: .claudeCode) == "low")
        #expect(Settings.resolvedEffort("max", for: .claudeCode) == "max")
        #expect(Settings.resolvedEffort("minimal", for: .claudeCode) == "low")
        #expect(Settings.resolvedEffort("", for: .claudeCode) == "low")
        #expect(Settings.resolvedEffort("", for: .openAI) == nil)
        #expect(Settings.resolvedEffort("minimal", for: .codex) == "minimal")

        let temporary = TemporaryDefaults()
        let settings = Settings(defaults: temporary.defaults, secrets: InMemorySecretStore())
        settings.timeoutSeconds = 1_000
        #expect(settings.timeoutSeconds == 300)
        #expect(Settings.storedTimeout(temporary.defaults) == 300)
    }
}
