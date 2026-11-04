import Foundation
@testable import QuickText

/// Records calls and returns a canned reply, optionally after a delay.
final class FakeBackend: LLMBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(system: String, user: String)] = []
    let output: String
    let delay: Duration?

    init(output: String, delay: Duration? = nil) {
        self.output = output
        self.delay = delay
    }

    var calls: [(system: String, user: String)] {
        lock.withLock { recorded }
    }

    func complete(system: String, user: String) async throws -> String {
        lock.withLock { recorded.append((system, user)) }
        if let delay { try await Task.sleep(for: delay) }
        return output
    }
}

/// A temporary shell script that stands in for `claude` or `codex`. `$DIR` in the script is its own
/// folder, which is deleted when the fake goes away.
final class FakeCLI {
    let directory: URL
    let executable: URL

    init(_ body: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickTextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("tool")
        let script = "#!/bin/sh\nDIR='\(directory.path)'\n" + body + "\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func claude(effort: String? = "low", timeout: TimeInterval = 10) -> ClaudeCodeBackend {
        ClaudeCodeBackend(configuration: ProviderConfiguration(
            provider: .claudeCode, effort: effort, timeout: timeout, executablePath: executable.path))
    }

    func codex(model: String = "", effort: String? = nil, timeout: TimeInterval = 10) -> CodexBackend {
        CodexBackend(configuration: ProviderConfiguration(
            provider: .codex, model: model, effort: effort, timeout: timeout, executablePath: executable.path))
    }

    func file(_ name: String) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    /// Arguments as written NUL-separated by the recording scripts.
    func arguments() -> [String] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("args")) else { return [] }
        var parts = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static let recordArguments = #"for a in "$@"; do printf '%s\0' "$a"; done > "$DIR/args""#

    /// Saves its arguments and stdin, then prints RESULT.
    static let recordingScript = """
        \(recordArguments)
        cat > "$DIR/stdin"
        echo "RESULT"
        """

    /// Like `codex exec`: saves its arguments and stdin, prints progress, writes ANSWER to the output file.
    static let codexScript = """
        \(recordArguments)
        cat > "$DIR/stdin"
        out=""; prev=""
        for a in "$@"; do
            if [ "$prev" = "--output-last-message" ]; then out="$a"; fi
            prev="$a"
        done
        echo "thinking… (progress noise)"
        printf 'ANSWER' > "$out"
        """
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]
    private(set) var writeCount = 0

    func read(_ account: String) -> String? {
        lock.withLock { secrets[account] }
    }

    func write(_ value: String, account: String) {
        lock.withLock {
            writeCount += 1
            secrets[account] = value.isEmpty ? nil : value
        }
    }
}

/// A throwaway UserDefaults domain.
final class TemporaryDefaults {
    let name = "QuickTextTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}
