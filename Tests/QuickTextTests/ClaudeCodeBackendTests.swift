import Darwin
import Foundation
import Testing
@testable import QuickText

@Suite struct ClaudeCodeBackendTests {
    @Test func textGoesThroughStdinOnly() async throws {
        let fake = try FakeCLI(FakeCLI.recordingScript)
        let secret = "my secret text 秘密"
        let output = try await fake.claude().complete(system: "SYS", user: secret)
        #expect(output == "RESULT\n")
        #expect(fake.file("stdin") == secret)
        #expect(!fake.arguments().contains { $0.contains("secret") })
    }

    @Test func argumentsAreCorrect() async throws {
        let fake = try FakeCLI(FakeCLI.recordingScript)
        _ = try await fake.claude().complete(system: "Be brief.", user: "hi")
        #expect(fake.arguments() == [
            "-p", "--system-prompt", "Be brief.", "--tools", "", "--model", "sonnet", "--effort", "low",
            "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands",
            "--settings", #"{"disableAllHooks":true}"#,
        ])
    }

    @Test func emptySystemPromptIsPassedAsAnEmptyArgument() async throws {
        let fake = try FakeCLI(FakeCLI.recordingScript)
        _ = try await fake.claude().complete(system: "", user: "hi")
        let args = fake.arguments()
        let index = try #require(args.firstIndex(of: "--system-prompt"))
        #expect(args[index + 1] == "")
        #expect(args.count == 14)
    }

    @Test func missingExecutableIsNotFound() async {
        let backend = ClaudeCodeBackend(configuration: ProviderConfiguration(
            provider: .claudeCode, executablePath: "/nonexistent/path/to/claude"))
        await #expect(throws: LLMError.notInstalled(.claudeCode)) {
            try await backend.complete(system: "", user: "hi")
        }
    }

    @Test func timeoutTerminatesWithinASecond() async throws {
        let fake = try FakeCLI("exec sleep 30")
        let start = Date()
        await #expect(throws: LLMError.timeout) {
            try await fake.claude(timeout: 0.3).complete(system: "", user: "hi")
        }
        #expect(Date().timeIntervalSince(start) < 1.3)
    }

    @Test func cancellingKillsTheProcess() async throws {
        let fake = try FakeCLI("echo $$ > \"$DIR/pid\"\nexec sleep 30")
        let backend = fake.claude()
        let task = Task { try await backend.complete(system: "", user: "hi") }

        var pid: Int32?
        for _ in 0..<300 where pid == nil {
            pid = fake.file("pid").flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if pid == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        let childPID = try #require(pid)

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(kill(childPID, 0) == -1)
    }

    @Test func backgroundChildHoldingThePipesDoesNotHang() async throws {
        // The script exits at once, but `sleep` inherits stdout and keeps it open.
        let fake = try FakeCLI("cat > /dev/null\nsleep 5 &\necho done")
        let start = Date()
        let output = try await fake.claude().complete(system: "", user: "hi")
        #expect(output == "done\n")
        #expect(Date().timeIntervalSince(start) < ProcessRun.drainGracePeriod + 1.5)
    }

    @Test func failuresAreClassified() async throws {
        let fake = try FakeCLI("echo 'some output'\nprintf 'line1\\nline2\\n\\nline3\\nline4\\nline5\\n' >&2\nexit 3")
        await #expect(throws: LLMError.processFailed(.claudeCode, exitCode: 3, detail: "line2\nline3\nline4\nline5")) {
            try await fake.claude().complete(system: "", user: "hi")
        }
        #expect(ClaudeCodeBackend.classifyFailure(exitCode: 1, stdout: "", stderr: "HTTP 401 Unauthorized")
                == .credentialsRejected(.claudeCode))
        #expect(ClaudeCodeBackend.classifyFailure(exitCode: 2, stdout: "only stdout", stderr: "")
                == .processFailed(.claudeCode, exitCode: 2, detail: "only stdout"))
        #expect(ClaudeCodeBackend.classifyFailure(exitCode: 2, stdout: "", stderr: "")
                == .processFailed(.claudeCode, exitCode: 2, detail: ""))
        #expect(LLMError.processFailed(.claudeCode, exitCode: 2, detail: "").message == "Claude Code failed (exit code 2).")
        // A successful run whose text mentions 401 is not an error.
        let ok = try FakeCLI("cat > /dev/null\necho 'error 401 in your text'")
        #expect(try await ok.claude().complete(system: "", user: "x") == "error 401 in your text\n")
    }

    @Test func expiredLoginIsRecognized() async throws {
        let fake = try FakeCLI("echo 'Invalid API key · Please run /login' >&2\nexit 1")
        await #expect(throws: LLMError.notLoggedIn(.claudeCode)) {
            try await fake.claude().complete(system: "", user: "hi")
        }
        #expect(ClaudeCodeBackend.classifyFailure(exitCode: 1, stdout: "OAuth session has expired", stderr: "")
                == .notLoggedIn(.claudeCode))
    }
}
