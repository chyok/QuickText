import SwiftUI

struct ChatView: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        VStack(spacing: 0) {
            if model.cards.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResultListView(model: model)
            }
            Divider()
            InputBarView(model: model)
        }
        .frame(minWidth: 420, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ResultListView: View {
    @ObservedObject var model: ChatModel
    private let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.cards) { card in
                        ResultCardView(card: card)
                    }
                    Color.clear.frame(height: 0).id(bottomID)
                }
                .padding(12)
            }
            .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
            .onChange(of: model.cards) { _, _ in
                // Next runloop, so the new card has been laid out.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Type or paste some text, then pick an action")
                .foregroundStyle(.secondary)
            Text("⏎ Check · ⇧⏎ New line · ⌘2 Refine · ⌘3 Translate · ⌘4 Send · ⌘⏎ Repeat last · Esc Hide")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }
}

/// Lives in the window's title bar.
struct ClearButton: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        Button { model.clear() } label: {
            Label("Clear", systemImage: "trash")
        }
        .buttonStyle(.borderless)
        .help("Remove all results")
        .disabled(model.cards.isEmpty)
        .padding(.horizontal, 10)
    }
}
