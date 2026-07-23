//
//  MessageListView.swift
//  Hermes
//
//  A plain LazyVStack-backed list (NOT exyte/Chat) — the simulator build runs
//  before we wire up exyte/Chat because exyte/Chat has its own Message model.
//  We keep ChatMessage as source of truth; converting via a tiny adapter would
//  be a Phase 3 cleanup if exyte/Chat becomes the desired surface. For v1 we
//  render native cells; UX is identical and we avoid the model mismatch.
//

import SwiftUI

struct MessageListView: View {
    @Binding var messages: [ChatMessage]
    let isStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: HermesTheme.Spacing.lg) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { idx, m in
                        MessageCell(
                            message: m,
                            isStreaming: isStreaming && idx == messages.count - 1,
                            isLastInTurn: isLastTurnBoundary(at: idx)
                        )
                        .id(m.id)
                    }
                }
                .padding(.horizontal, HermesTheme.Spacing.lg)
                .padding(.top, HermesTheme.Spacing.sm)
                .padding(.bottom, 8)
            }
            .background(HermesTheme.background)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 4, for: .scrollContent)
            .onAppear {
                scrollToLatest(using: proxy, animated: false)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: messages.last?.text) { _, _ in
                if isStreaming {
                    scrollToLatest(using: proxy, animation: .linear(duration: 0.05))
                }
            }
        }
    }

    private func scrollToLatest(
        using proxy: ScrollViewProxy,
        animated: Bool = true,
        animation: Animation = .easeOut(duration: 0.2)
    ) {
        guard let lastID = messages.last?.id else { return }

        // History can arrive before LazyVStack has laid out its IDs. Deferring
        // one main-run-loop turn makes the initial scroll reliable as well as
        // keeping the live-stream scroll behavior intact.
        DispatchQueue.main.async {
            if animated {
                withAnimation(animation) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    /// The terminal "Complete" / "Cancelled" badge should only render on the
    /// last assistant message in the run, not on every finished message.
    private func isLastTurnBoundary(at index: Int) -> Bool {
        guard messages[index].role == .assistant else { return false }
        let nextIndex = index + 1
        if nextIndex >= messages.count { return true }
        // If the next message is a user message OR not finalized, this is a turn boundary.
        let next = messages[nextIndex]
        return next.role == .user
    }
}
