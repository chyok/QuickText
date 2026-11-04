import Foundation
import Testing
@testable import QuickText

@Suite struct CodexBackendTests {
    @Test func argumentsStdinAndFinalMessage() async throws {
        let fake = try FakeCLI(FakeCLI.codexScript)
        let output = try await fake.codex(model: "gpt-6.1-sol", effort: "low")
            .complete(system: "Fix \"typos\".\nOutput only the text.", user: "my secret text 秘密")

        // The answer comes from the output file, not from the progress on stdout.
        #expect(output == "ANSWER")
        #expect(fake.file("stdin") == "my secret text 秘密")

        let args = fake.arguments()
        #expect(Array(args.prefix(9)) == [
            "exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--color", "never",
            "--output-last-message", args[8],
        ])
        #expect(Array(args.dropFirst(9)) == [
            "--model", "gpt-6.1-sol",
            "--config", #"model_reasoning_effort="low""#,
            "--config", #"developer_instructions="Fix \"typos\".\nOutput only the text.""#,
            "-",
        ])
        #expect(!args.contains { $0.contains("secret") })
        // The temporary output file is cleaned up.
        #expect(!FileManager.default.fileExists(atPath: args[8]))
    }

    @Test func defaultsAndSendLeaveOptionsOut() async throws {
        let fake = try FakeCLI(FakeCLI.codexScript)
        _ = try await fake.codex(model: "", effort: nil).complete(system: "", user: "What is 2+2?")
        let args = fake.arguments()
        #expect(!args.contains("--model"))
        #expect(!args.contains("--config"))
        #expect(args.last == "-")
    }

    @Test func tomlStrings() {
        #expect(CodexBackend.tomlString("plain") == #""plain""#)
        #expect(CodexBackend.tomlString("a\"b\\c") == #""a\"b\\c""#)
        #expect(CodexBackend.tomlString("line\nnext\ttab") == #""line\nnext\ttab""#)
        #expect(CodexBackend.tomlString("bell\u{07}") == #""bell\u0007""#)
        #expect(CodexBackend.tomlString("简体中文 ✓") == "\"简体中文 ✓\"")
    }

    @Test func missingExecutableIsNotInstalled() async {
        let backend = CodexBackend(configuration: ProviderConfiguration(
            provider: .codex, executablePath: "/nonexistent/codex"))
        await #expect(throws: LLMError.notInstalled(.codex)) {
            try await backend.complete(system: "", user: "hi")
        }
    }

    @Test func failuresAreClassified() async throws {
        let loggedOut = try FakeCLI("echo 'Error: Not logged in. Run codex login.' >&2\nexit 1")
        await #expect(throws: LLMError.notLoggedIn(.codex)) {
            try await loggedOut.codex().complete(system: "", user: "hi")
        }
        let broken = try FakeCLI("echo 'model not found' >&2\nexit 2")
        await #expect(throws: LLMError.processFailed(.codex, exitCode: 2, detail: "model not found")) {
            try await broken.codex().complete(system: "", user: "hi")
        }
        #expect(LLMError.notLoggedIn(.codex).message == "Codex isn't logged in. Run `codex login` in Terminal.")
    }
}
