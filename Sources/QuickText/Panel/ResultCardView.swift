import AppKit
import SwiftUI

extension TextActionKind {
    var color: Color {
        switch self {
        case .check: return .orange
        case .refine: return .purple
        case .translate: return .blue
        case .send: return .teal
        }
    }

    var icon: String {
        switch self {
        case .check: return "text.badge.checkmark"
        case .refine: return "wand.and.stars"
        case .translate: return "character.bubble"
        case .send: return "paperplane"
        }
    }
}

struct ResultCardView: View {
    let card: ResultCard
    /// When Copy was last clicked; "Copied" shows for 1.5 s after that.
    @StateObject private var copiedAt = LocalState<Date?>(nil)
    @StateObject private var showOriginal = LocalState(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            originalSection
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Label(card.action.title, systemImage: card.action.kind.icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(card.action.kind.color)
            if case let .done(.check(result)) = card.status {
                badge(for: result)
            }
            Spacer(minLength: 0)
            if case let .done(result) = card.status {
                if let elapsed = card.elapsed {
                    Text(String(format: "%.1fs", elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Button { copy(result.copyText) } label: {
                    Label(copiedAt.value == nil ? "Copy" : "Copied",
                          systemImage: copiedAt.value == nil ? "doc.on.doc" : "checkmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(card.action == .check ? "Copy the corrected text" : "Copy the result")
            }
        }
    }

    @ViewBuilder
    private func badge(for result: CheckResult) -> some View {
        if result.hasChanges {
            Badge(text: plural(result.changeCount, "change"), color: .orange)
        } else if !result.notes.isEmpty {
            Badge(text: plural(result.notes.count, "suggestion"), color: .orange)
        } else {
            Badge(text: "No errors", color: .green)
        }
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let now = Date()
        copiedAt.value = now
        let state = copiedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // A later click restarts the 1.5 s.
            if state.value == now { state.value = nil }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch card.status {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Text("\(card.action.loadingText) \(String(format: "%.1fs", context.date.timeIntervalSince(card.startedAt)))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case let .done(.check(result)):
            CheckResultView(result: result)
        case let .done(.text(text)):
            Text(card.action == .send ? DiffRenderer.markdown(text) : AttributedString(text))
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Label {
                Text(message).textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.red)
        }
    }

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showOriginal.value.toggle() }
            } label: {
                Label(showOriginal.value ? "Hide original" : "Show original",
                      systemImage: showOriginal.value ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showOriginal.value {
                Text(card.source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
