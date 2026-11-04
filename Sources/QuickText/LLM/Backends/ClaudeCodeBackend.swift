import Foundation
import os

/// Runs the locally installed, already logged-in Claude Code CLI (`claude -p`).
struct ClaudeCodeBackend: LLMBackend {
    let configuration: ProviderConfiguration

    static func arguments(system: String, model: String, effort: String?) -> [String] {
        var arguments = [
            "-p",
            // Always passed, even when empty: without it Claude Code uses its own coding-assistant prompt.
            "--system-prompt", system,
            "--tools", "",
            "--model", model,
        ]
        if let effort {
            arguments += ["--effort", effort]
        }
        arguments += [
            "--no-session-persistence",
            // Skip MCP servers and skills: faster startup, and no grandchildren left behind on cancel.
            "--strict-mcp-config",
            "--disable-slash-commands",
            // Hooks from the user's settings or plugins would inject their own instructions.
            "--settings", #"{"disableAllHooks":true}"#,
        ]
        return arguments
    }

    func complete(system: String, user: String) async throws -> String {
        guard let executable = ExecutableLocator.locate("claude", customPath: configuration.executablePath) else {
            throw LLMError.notInstalled(.claudeCode)
        }
        let run = ProcessRun(
            provider: .claudeCode,
            executable: executable,
            arguments: Self.arguments(system: system, model: configuration.model, effort: configuration.effort),
            input: Data(user.utf8),
            timeout: configuration.timeout
        )
        let output = try await run.run()
        Logger.backend.info("claude exited with status \(output.exitCode), \(output.stdout.count) bytes out")
        return try Self.interpret(output)
    }

    static func interpret(_ output: ProcessRun.Output) throws -> String {
        let stdout = String(decoding: output.stdout, as: UTF8.self)
        guard output.exitCode == 0 else {
            let stderr = String(decoding: output.stderr, as: UTF8.self)
            throw classifyFailure(exitCode: output.exitCode, stdout: stdout, stderr: stderr)
        }
        return stdout
    }

    /// Only called for a non-zero exit code: the user's own text may well contain "401".
    static func classifyFailure(exitCode: Int32, stdout: String, stderr: String) -> LLMError {
        let combined = (stderr + "\n" + stdout).lowercased()
        if ["session has expired", "auth login", "not logged in", "/login"].contains(where: combined.contains) {
            return .notLoggedIn(.claudeCode)
        }
        if combined.contains("401") {
            return .credentialsRejected(.claudeCode)
        }
        return .processFailed(.claudeCode, exitCode: exitCode,
                              detail: CommandLineEnvironment.tail(stdout: stdout, stderr: stderr))
    }
}
