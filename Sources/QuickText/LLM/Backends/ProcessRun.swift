import Darwin
import Foundation
import os

extension Logger {
    static let backend = Logger(subsystem: "io.github.chyok.QuickText", category: "backend")
}

/// How command-line tools are started.
enum CommandLineEnvironment {
    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let original = env["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = ExecutableLocator.standardDirectories.joined(separator: ":") + ":" + original
        // If the app was started from inside a Claude Code session, the child must not think it is nested.
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        return env
    }

    /// An always-empty directory, so no project instructions (CLAUDE.md, AGENTS.md) are picked up.
    static func workingDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QuickText-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The last `count` non-empty lines of stderr (or stdout when stderr is empty), for error messages.
    static func tail(stdout: String, stderr: String, count: Int = 4) -> String {
        let source = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr
        return source.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(count)
            .joined(separator: "\n")
    }
}

// MARK: - Reading a pipe

/// Collects a pipe's output in the background until EOF.
final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let finished = DispatchSemaphore(value: 0)
    private let handle: FileHandle

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.finished.signal()
            } else {
                self.lock.withLock { self.data.append(chunk) }
            }
        }
    }

    /// Everything read once the pipe hits EOF, or nil if the deadline passes first.
    func waitForEOF(until deadline: DispatchTime) -> Data? {
        guard finished.wait(timeout: deadline) == .success else {
            stop()
            return nil
        }
        return lock.withLock { data }
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    /// Whatever has arrived so far.
    var partialData: Data {
        lock.withLock { data }
    }
}

// MARK: - One child process

final class ProcessRun: @unchecked Sendable {
    struct Output: Equatable, Sendable {
        var exitCode: Int32
        var stdout: Data
        var stderr: Data
    }

    /// How long to keep reading after the process exits. A grandchild that inherited
    /// the pipes would otherwise keep them open and hang the request.
    static let drainGracePeriod: TimeInterval = 2

    private static let registryLock = NSLock()
    private static var running: [ObjectIdentifier: Process] = [:]

    private let provider: Provider
    private let process = Process()
    private let input: Data
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var started = false
    private var exited = false
    private var cancelled = false
    private var timedOut = false

    init(provider: Provider, executable: URL, arguments: [String], input: Data, timeout: TimeInterval) {
        self.provider = provider
        process.executableURL = executable
        process.arguments = arguments
        process.environment = CommandLineEnvironment.environment()
        process.currentDirectoryURL = CommandLineEnvironment.workingDirectory()
        self.input = input
        self.timeout = timeout
    }

    func run() async throws -> Output {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(_ continuation: CheckedContinuation<Output, Error>) {
        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Read both pipes from the start, so a full pipe can never block the child.
        let stdout = PipeReader(stdoutPipe), stderr = PipeReader(stderrPipe)

        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // A process that has already exited finished in time, however close the call.
            let expired = self.lock.withLock {
                if !self.exited { self.timedOut = true }
                return self.timedOut
            }
            if expired { Self.terminate(self.process) }
        }
        let key = ObjectIdentifier(self)

        process.terminationHandler = { [self] process in
            lock.withLock { exited = true }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let deadline = DispatchTime.now() + Self.drainGracePeriod
                let out = stdout.waitForEOF(until: deadline) ?? stdout.partialData
                let err = stderr.waitForEOF(until: deadline) ?? stderr.partialData
                timer.cancel()
                Self.registryLock.withLock { _ = Self.running.removeValue(forKey: key) }

                let (wasCancelled, didTimeOut) = lock.withLock { (cancelled, timedOut) }
                if wasCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if didTimeOut {
                    continuation.resume(throwing: LLMError.timeout)
                } else {
                    continuation.resume(returning: Output(exitCode: process.terminationStatus, stdout: out, stderr: err))
                }
            }
        }

        lock.lock()
        if cancelled {
            lock.unlock()
            stdout.stop()
            stderr.stop()
            continuation.resume(throwing: CancellationError())
            return
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            stdout.stop()
            stderr.stop()
            Logger.backend.error("failed to launch \(self.provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            continuation.resume(throwing: LLMError.notInstalled(provider))
            return
        }
        started = true
        lock.unlock()

        Self.registryLock.withLock { Self.running[key] = process }

        let input = self.input
        DispatchQueue.global(qos: .userInitiated).async {
            // write(contentsOf:) throws on EPIPE instead of raising an Objective-C exception.
            try? stdinPipe.fileHandleForWriting.write(contentsOf: input)
            // Both tools start working only once stdin hits EOF.
            try? stdinPipe.fileHandleForWriting.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
    }

    private func cancel() {
        let wasStarted = lock.withLock {
            cancelled = true
            return started
        }
        if wasStarted { Self.terminate(process) }
    }

    /// SIGTERM, then SIGKILL if it is still around after 2 seconds.
    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// Called on quit: SIGTERM everything, wait up to 0.5 s, then SIGKILL what is left.
    static func terminateAll() {
        let processes = registryLock.withLock { Array(running.values) }
        for process in processes where process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline, processes.contains(where: \.isRunning) {
            usleep(20_000)
        }
        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
