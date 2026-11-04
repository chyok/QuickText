import Foundation

protocol LLMBackend: Sendable {
    /// Returns the model's complete output. Cancelling the calling Task must stop the request.
    func complete(system: String, user: String) async throws -> String
}

enum LLMError: Error, Equatable {
    /// The command-line tool isn't installed, or the chosen path is wrong.
    case notInstalled(Provider)
    case notLoggedIn(Provider)
    case missingAPIKey(Provider)
    /// HTTP 401 / 403.
    case credentialsRejected(Provider)
    case rateLimited(Provider)
    case overloaded(Provider)
    /// The model declined to answer.
    case refused(Provider)
    case requestFailed(Provider, status: Int, message: String)
    case processFailed(Provider, exitCode: Int32, detail: String)
    case network(Provider, String)
    case timeout
    case emptyResult

    var message: String {
        switch self {
        case let .notInstalled(provider):
            return "\(provider.displayName) not found. Install it, or set its path in Settings."
        case .notLoggedIn(.codex):
            return "Codex isn't logged in. Run `codex login` in Terminal."
        case .notLoggedIn:
            return "Your Claude login has expired. Run `claude auth login` in Terminal."
        case let .missingAPIKey(provider):
            return "Add your \(provider.displayName) key in Settings."
        case .credentialsRejected(.claudeCode):
            return "Claude rejected the current credentials (401). Log in again, or check `~/.claude/settings.json`."
        case let .credentialsRejected(provider):
            return "\(provider.serviceName) rejected the API key. Check it in Settings."
        case let .rateLimited(provider):
            return "\(provider.serviceName) is limiting requests right now. Wait a moment and try again."
        case let .overloaded(provider):
            return "\(provider.serviceName) is overloaded right now. Try again in a moment."
        case let .refused(provider):
            return "\(provider.serviceName) declined to answer this request."
        case let .requestFailed(provider, status, message):
            let prefix = "\(provider.displayName) error (HTTP \(status))"
            return message.isEmpty ? prefix + "." : prefix + ": " + message
        case let .processFailed(provider, exitCode, detail):
            let prefix = "\(provider.displayName) failed (exit code \(exitCode))"
            return detail.isEmpty ? prefix + "." : prefix + ":\n" + detail
        case let .network(provider, description):
            return "Couldn't reach \(provider.serviceName): \(description)"
        case .timeout:
            return "The request timed out. Please try again."
        case .emptyResult:
            return "The model returned nothing. Please try again."
        }
    }
}
