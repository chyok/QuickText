import Foundation
import os

/// Runs the locally installed, already logged-in Codex CLI (`codex exec`).
struct CodexBackend: LLMBackend {
    let configuration: ProviderConfiguration

    /// The prompt goes on stdin (`-`); the final answer is written to `outputFile`.
    static func arguments(system: String, model: String, effort: String?, outputFile: String) -> [String] {
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox", "read-only",
            "--color", "never",
            "--output-last-message", outputFile,
        ]
        if !model.isEmpty {
            arguments += ["--model", model]
        }
        if let effort {
            arguments += ["--config", "model_reasoning_effort=" + tomlString(effort)]
        }
        if !system.isEmpty {
            arguments += ["--config", "developer_instructions=" + tomlString(system)]
        }
        arguments.append("-")
        return arguments
    }

    /// `--config` values are parsed as TOML, so strings are passed as quoted TOML strings.
    static func tomlString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    func complete(system: String, user: String) async throws -> String {
        guard let executable = ExecutableLocator.locate("codex", customPath: configuration.executablePath) else {
            throw LLMError.notInstalled(.codex)
        }
        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickText-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        let run = ProcessRun(
            provider: .codex,
            executable: executable,
            arguments: Self.arguments(system: system, model: configuration.model,
                                      effort: configuration.effort, outputFile: outputFile.path),
            input: Data(user.utf8),
            timeout: configuration.timeout
        )
        let output = try await run.run()
        Logger.backend.info("codex exited with status \(output.exitCode), \(output.stdout.count) bytes out")

        guard output.exitCode == 0 else {
            throw Self.classifyFailure(exitCode: output.exitCode,
                                       stdout: String(decoding: output.stdout, as: UTF8.self),
                                       stderr: String(decoding: output.stderr, as: UTF8.self))
        }
        return (try? String(contentsOf: outputFile, encoding: .utf8)) ?? ""
    }

    /// Only called for a non-zero exit code.
    static func classifyFailure(exitCode: Int32, stdout: String, stderr: String) -> LLMError {
        let combined = (stderr + "\n" + stdout).lowercased()
        if ["not logged in", "codex login", "401", "unauthorized"].contains(where: combined.contains) {
            return .notLoggedIn(.codex)
        }
        return .processFailed(.codex, exitCode: exitCode,
                              detail: CommandLineEnvironment.tail(stdout: stdout, stderr: stderr))
    }
}
