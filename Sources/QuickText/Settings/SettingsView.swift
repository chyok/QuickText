import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @StateObject private var launchAtLogin = LocalState(false)
    @StateObject private var loginError = LocalState<String?>(nil)
    @StateObject private var detection = LocalState<Detection>(.searching)

    enum Detection: Equatable {
        case searching
        case found(String)
        case notFound
    }

    private var provider: Provider { settings.provider }

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show / hide window", name: .togglePanel)
            }

            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
                }
                if !provider.isCommandLineTool {
                    SecureField("API key", text: $settings.apiKey, prompt: Text(provider == .anthropic ? "sk-ant-…" : "sk-…"))
                }
                TextField("Model", text: $settings.model,
                          prompt: Text(provider.defaultModel.isEmpty ? "\(provider.displayName) default" : provider.defaultModel))
                Picker("Reasoning effort", selection: $settings.effort) {
                    if provider.defaultEffort == nil {
                        Text("Model default").tag("")
                    }
                    ForEach(provider.efforts, id: \.self) { Text($0).tag($0) }
                }
                if provider == .openAI {
                    TextField("Base URL", text: $settings.baseURL, prompt: Text(Provider.openAI.defaultBaseURL?.absoluteString ?? ""))
                    if !settings.baseURL.trimmingCharacters(in: .whitespaces).isEmpty,
                       Settings.validBaseURL(settings.baseURL) == nil {
                        status("Enter an http or https URL.", "xmark.octagon.fill", .red)
                    }
                }
                if let name = provider.executableName {
                    HStack {
                        TextField("\(name) path", text: $settings.executablePath,
                                  prompt: Text(detectedPath ?? "Auto-detect"))
                        Button("Choose…") { choosePath(name) }
                        if !settings.executablePath.isEmpty {
                            Button("Auto-detect") { settings.executablePath = "" }
                        }
                    }
                    pathStatus(name)
                }
            } header: {
                Text("Model")
            } footer: {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $settings.timeoutSeconds, in: Settings.timeoutRange, step: 5) {
                    LabeledContent("Request timeout", value: "\(settings.timeoutSeconds) s")
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.value },
                    set: setLaunchAtLogin
                ))
                if let error = loginError.value {
                    Text("Couldn't change it: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLogin.value = LoginItem.isEnabled
            loginError.value = nil
            detect()
        }
        .onChange(of: settings.provider) { _, _ in detect() }
    }

    private var footer: String {
        let search = "Leave the path empty to search ~/.local/bin, /opt/homebrew/bin and /usr/local/bin, then your login shell's PATH."
        switch provider {
        case .claudeCode:
            return "Uses your Claude Code login. sonnet explains Check changes best; haiku is a little faster but less reliable. " + search
        case .codex:
            return "Uses your Codex login (codex login). Leave Model empty for Codex's default. " + search
        case .anthropic:
            return "Pay as you go with an API key from the Claude Console. The key is stored in your Keychain."
        case .openAI:
            return "Works with OpenAI and any server that speaks its Chat Completions API. For Ollama, use http://localhost:11434/v1 and leave the key empty. The key is stored in your Keychain."
        }
    }

    private var detectedPath: String? {
        if case let .found(path) = detection.value { return path }
        return nil
    }

    @ViewBuilder
    private func pathStatus(_ name: String) -> some View {
        let manual = settings.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if !manual.isEmpty {
                if ExecutableLocator.isExecutableFile(ExecutableLocator.expand(manual)) {
                    status("Using this path", "checkmark.circle.fill", .green)
                } else {
                    status("This path doesn't exist or isn't executable", "xmark.octagon.fill", .red)
                }
            } else {
                switch detection.value {
                case .searching:
                    status("Looking for \(name)…", "magnifyingglass", .secondary)
                case let .found(path):
                    status("Found: \(path)", "checkmark.circle.fill", .green)
                case .notFound:
                    status("\(provider.displayName) not found. Install it, or choose its path.",
                           "exclamationmark.triangle.fill", .orange)
                }
            }
        }
    }

    private func status(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private func detect() {
        guard let name = provider.executableName else { return }
        detection.value = .searching
        let state = detection, settings = settings
        DispatchQueue.global(qos: .userInitiated).async {
            let path = ExecutableLocator.autoDetect(name)
            DispatchQueue.main.async {
                // Ignore a late answer for a provider that is no longer selected.
                guard settings.provider.executableName == name else { return }
                state.value = path.map(Detection.found) ?? .notFound
            }
        }
    }

    private func choosePath(_ name: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose the \(name) executable"
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.executablePath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError.value = nil
        } catch {
            loginError.value = error.localizedDescription
        }
        launchAtLogin.value = LoginItem.isEnabled
    }
}
