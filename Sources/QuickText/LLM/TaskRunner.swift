import Foundation

/// The action a button triggers.
enum TextActionKind: Equatable, Sendable {
    case check, refine, translate, send
}

/// A fully resolved action (style and translation direction already chosen).
enum TextAction: Equatable, Sendable {
    case check
    case refine(RefineStyle)
    case translate(TranslationDirection)
    case send

    var kind: TextActionKind {
        switch self {
        case .check: return .check
        case .refine: return .refine
        case .translate: return .translate
        case .send: return .send
        }
    }

    var title: String {
        switch self {
        case .check: return "Check"
        case let .refine(style): return "Refine · \(style.displayName)"
        case let .translate(direction): return "Translate · \(direction.label)"
        case .send: return "Send"
        }
    }

    var loadingText: String {
        switch self {
        case .check: return "Checking…"
        case .refine: return "Refining…"
        case .translate: return "Translating…"
        case .send: return "Thinking…"
        }
    }
}

struct CheckResult: Equatable, Sendable {
    var corrected: String
    var segments: [DiffSegment]
    var notes: [String]

    var hasChanges: Bool { segments.contains { $0.kind != .equal } }
    var changeCount: Int { DiffEngine.changeCount(segments) }
}

enum CardResult: Equatable, Sendable {
    case check(CheckResult)
    case text(String)

    var copyText: String {
        switch self {
        case let .check(result): return result.corrected
        case let .text(text): return text
        }
    }
}

struct TaskRunner: Sendable {
    let backend: LLMBackend

    static func resolve(_ kind: TextActionKind, text: String, refineStyle: RefineStyle) -> TextAction {
        switch kind {
        case .check: return .check
        case .refine: return .refine(refineStyle)
        case .translate: return .translate(LanguageDetector.direction(for: text))
        case .send: return .send
        }
    }

    static func systemPrompt(for action: TextAction) -> String {
        switch action {
        case .check: return Prompts.system(Prompts.check)
        case let .refine(style): return Prompts.system(Prompts.refine(style))
        case let .translate(direction): return Prompts.system(Prompts.translate(direction))
        case .send: return ""
        }
    }

    static func userMessage(for action: TextAction, text: String) -> String {
        action == .send ? text : Prompts.wrapUser(text)
    }

    func perform(_ action: TextAction, text: String) async throws -> CardResult {
        let output = try await backend.complete(
            system: Self.systemPrompt(for: action),
            user: Self.userMessage(for: action, text: text)
        )

        if action == .send {
            let answer = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw LLMError.emptyResult }
            return .text(answer)
        }

        let cleaned = Prompts.cleanOutput(output)
        guard !cleaned.isEmpty else { throw LLMError.emptyResult }

        guard action == .check else { return .text(cleaned) }

        let parsed = CheckOutputParser.parse(cleaned)
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A reply with notes but no body must not diff the user's text into one big deletion.
        let corrected = parsed.corrected.isEmpty ? original : parsed.corrected
        return .check(CheckResult(
            corrected: corrected,
            segments: DiffEngine.diff(old: original, new: corrected),
            notes: CheckOutputParser.usableNotes(parsed.notes)
        ))
    }
}
