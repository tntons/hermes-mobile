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
                LazyVStack(spacing: 14) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { idx, m in
                        MessageCell(
                            message: m,
                            isStreaming: isStreaming && idx == messages.count - 1,
                            isLastInTurn: isLastTurnBoundary(at: idx)
                        )
                        .id(m.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.last?.text) { _, _ in
                if let last = messages.last, isStreaming {
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
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
