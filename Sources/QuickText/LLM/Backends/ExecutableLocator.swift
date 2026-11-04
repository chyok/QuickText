import Darwin
import Foundation

/// Finds a command-line tool such as `claude` or `codex`.
enum ExecutableLocator {
    /// Searched first, and put in front of PATH for the child process.
    static let standardDirectories = [
        NSHomeDirectory() + "/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    static func expand(_ path: String) -> String {
        (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    /// A manual path is used as is (or fails); otherwise auto-detect.
    static func locate(_ name: String, customPath: String?) -> URL? {
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = expand(customPath)
            return isExecutableFile(path) ? URL(fileURLWithPath: path) : nil
        }
        return autoDetect(name).map { URL(fileURLWithPath: $0) }
    }

    /// Blocking; may take up to 5 seconds when it falls back to the login shell.
    static func autoDetect(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name], isExecutableFile(cached) { return cached }
        let found = standardDirectories.map { "\($0)/\(name)" }.first(where: isExecutableFile)
            ?? loginShellLookup(name)
        cache[name] = found
        return found
    }

    /// The user's login shell (zsh, bash, fish…), so PATH set up in their dotfiles applies.
    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if isExecutableFile(path) { return path }
        }
        return "/bin/zsh"
    }

    private static func loginShellLookup(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell)
        process.arguments = ["-l", "-c", "command -v \(name)"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }

        let reader = PipeReader(pipe)
        guard let data = reader.waitForEOF(until: .now() + 5) else {
            process.terminate()
            return nil
        }
        // Dotfiles may print other things first; the answer is the last absolute path.
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && isExecutableFile($0) }
    }
}
