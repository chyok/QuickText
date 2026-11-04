import Foundation

struct ResultCard: Identifiable, Equatable {
    enum Status: Equatable {
        case loading
        case done(CardResult)
        case failed(String)
        case cancelled
    }

    let id: UUID
    let action: TextAction
    /// The text as submitted, shown under "Show original".
    let source: String
    let startedAt: Date
    var status: Status = .loading
    var finishedAt: Date?

    init(action: TextAction, source: String, id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.action = action
        self.source = source
        self.startedAt = startedAt
    }

    var isLoading: Bool { status == .loading }

    var elapsed: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

/// Window state: input, cards, and the one request in flight.
@MainActor
final class ChatModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var cards: [ResultCard] = []
    @Published var refineStyle: RefineStyle {
        didSet { settings?.refineStyle = refineStyle }
    }

    let inputBridge = InputBridge()
    private let runner: TaskRunner
    private let settings: Settings?
    private(set) var currentTask: Task<Void, Never>?
    private var currentCardID: UUID?
    private(set) var lastKind: TextActionKind?

    init(runner: TaskRunner, settings: Settings? = .shared) {
        self.runner = runner
        self.settings = settings
        refineStyle = settings?.refineStyle ?? .natural
    }

    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(_ kind: TextActionKind) {
        guard canRun else { return }
        cancelCurrent()

        let text = input
        input = ""
        let action = TaskRunner.resolve(kind, text: text, refineStyle: refineStyle)
        let card = ResultCard(action: action, source: text)
        cards.append(card)
        lastKind = kind
        currentCardID = card.id

        let runner = self.runner
        currentTask = Task { [weak self] in
            do {
                let result = try await runner.perform(action, text: text)
                self?.finish(card.id, status: .done(result))
            } catch is CancellationError {
                // Already marked as cancelled.
            } catch let error as LLMError {
                self?.finish(card.id, status: .failed(error.message))
            } catch {
                self?.finish(card.id, status: .failed(error.localizedDescription))
            }
        }
        inputBridge.focusAndSelectAll()
    }

    func repeatLast() {
        run(lastKind ?? .check)
    }

    func clear() {
        cancelCurrent()
        cards.removeAll()
    }

    private func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
        if let id = currentCardID {
            finish(id, status: .cancelled)
        }
        currentCardID = nil
    }

    /// Only a card that is still loading changes, so a late result can't overwrite "Cancelled".
    private func finish(_ id: UUID, status: ResultCard.Status) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].isLoading else { return }
        cards[index].status = status
        cards[index].finishedAt = Date()
        if currentCardID == id {
            currentCardID = nil
        }
    }
}
