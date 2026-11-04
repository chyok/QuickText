import Foundation
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.k, modifiers: [.control, .option]))
}

/// User preferences, saved on every change: UserDefaults for settings, the Keychain for API keys.
/// Each provider keeps its own model, effort, path and key; the fields below show the selected one's.
final class Settings: ObservableObject {
    static let shared = Settings()

    enum Key {
        static let provider = "provider"
        static let timeout = "timeoutSeconds"
        static let refineStyle = "refine.style"
        static let hasLaunchedBefore = "app.hasLaunchedBefore"

        static func model(_ provider: Provider) -> String { provider.rawValue + ".model" }
        static func effort(_ provider: Provider) -> String { provider.rawValue + ".effort" }
        static func path(_ provider: Provider) -> String { provider.rawValue + ".path" }
        static func baseURL(_ provider: Provider) -> String { provider.rawValue + ".baseURL" }
    }

    static let timeoutRange = 5...300
    static let defaultTimeout = 30

    private let defaults: UserDefaults
    private let secrets: SecretStore
    /// Set while the fields are filled in for another provider, so that doesn't count as an edit.
    private var isLoadingProvider = false

    @Published var provider: Provider {
        didSet {
            defaults.set(provider.rawValue, forKey: Key.provider)
            loadFields()
        }
    }

    /// Empty means the provider's default.
    @Published var model = "" { didSet { save(model, forKey: Key.model(provider)) } }
    /// Empty means the parameter isn't sent (only offered where `defaultEffort` is nil).
    @Published var effort = "" { didSet { save(effort, forKey: Key.effort(provider)) } }
    /// Command-line tools only; empty means auto-detect.
    @Published var executablePath = "" { didSet { save(executablePath, forKey: Key.path(provider)) } }
    /// OpenAI only; empty means api.openai.com.
    @Published var baseURL = "" { didSet { save(baseURL, forKey: Key.baseURL(provider)) } }
    /// API providers only; kept in the Keychain.
    @Published var apiKey = "" {
        didSet {
            guard !isLoadingProvider else { return }
            secrets.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.rawValue)
        }
    }

    @Published var timeoutSeconds: Int {
        didSet {
            // Assigning inside didSet does not call didSet again, so save the clamped value here.
            let clamped = Self.clampTimeout(timeoutSeconds)
            if clamped != timeoutSeconds { timeoutSeconds = clamped }
            defaults.set(clamped, forKey: Key.timeout)
        }
    }

    @Published var refineStyle: RefineStyle {
        didSet { defaults.set(refineStyle.rawValue, forKey: Key.refineStyle) }
    }

    init(defaults: UserDefaults = .standard, secrets: SecretStore = Keychain()) {
        self.defaults = defaults
        self.secrets = secrets
        provider = Self.storedProvider(defaults)
        timeoutSeconds = Self.storedTimeout(defaults)
        refineStyle = defaults.string(forKey: Key.refineStyle).flatMap(RefineStyle.init(rawValue:)) ?? .natural
        loadFields()
    }

    private func loadFields() {
        isLoadingProvider = true
        defer { isLoadingProvider = false }
        model = defaults.string(forKey: Key.model(provider)) ?? ""
        effort = Self.resolvedEffort(defaults.string(forKey: Key.effort(provider)), for: provider) ?? ""
        executablePath = defaults.string(forKey: Key.path(provider)) ?? ""
        baseURL = defaults.string(forKey: Key.baseURL(provider)) ?? ""
        apiKey = provider.isCommandLineTool ? "" : secrets.read(provider.rawValue) ?? ""
    }

    private func save(_ value: String, forKey key: String) {
        guard !isLoadingProvider else { return }
        defaults.set(value, forKey: key)
    }

    // MARK: Reading for requests

    /// Reads UserDefaults and the Keychain directly, so the backend can call it from any thread for every request.
    static func configuration(defaults: UserDefaults = .standard,
                              secrets: SecretStore = Keychain()) -> ProviderConfiguration {
        configuration(for: storedProvider(defaults), defaults: defaults, secrets: secrets)
    }

    static func configuration(for provider: Provider, defaults: UserDefaults,
                              secrets: SecretStore) -> ProviderConfiguration {
        func stored(_ key: String) -> String? {
            let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return ProviderConfiguration(
            provider: provider,
            model: stored(Key.model(provider)),
            effort: resolvedEffort(defaults.string(forKey: Key.effort(provider)), for: provider),
            timeout: TimeInterval(storedTimeout(defaults)),
            executablePath: provider.isCommandLineTool ? stored(Key.path(provider)) : nil,
            apiKey: provider.isCommandLineTool ? nil : secrets.read(provider.rawValue),
            baseURL: stored(Key.baseURL(provider)).flatMap(validBaseURL)
        )
    }

    static func storedProvider(_ defaults: UserDefaults) -> Provider {
        defaults.string(forKey: Key.provider).flatMap(Provider.init(rawValue:)) ?? .claudeCode
    }

    static func storedTimeout(_ defaults: UserDefaults) -> Int {
        clampTimeout(defaults.object(forKey: Key.timeout) as? Int ?? defaultTimeout)
    }

    /// nil (never chosen) → the provider's default; "" → not sent; anything unknown → the default.
    static func resolvedEffort(_ stored: String?, for provider: Provider) -> String? {
        guard let stored else { return provider.defaultEffort }
        if stored.isEmpty && provider.defaultEffort == nil { return nil }
        return provider.efforts.contains(stored) ? stored : provider.defaultEffort
    }

    /// An http(s) URL with a host, or nil.
    static func validBaseURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func clampTimeout(_ value: Int) -> Int {
        min(max(value, timeoutRange.lowerBound), timeoutRange.upperBound)
    }

    /// True only the very first time it is called.
    func consumeFirstLaunch() -> Bool {
        guard defaults.object(forKey: Key.hasLaunchedBefore) == nil else { return false }
        defaults.set(true, forKey: Key.hasLaunchedBefore)
        return true
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
