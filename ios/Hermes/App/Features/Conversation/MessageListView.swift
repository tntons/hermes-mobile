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
                LazyVStack(spacing: 12) {
                    ForEach(messages) { m in
                        MessageCell(message: m, isStreaming: isStreaming)
                            .id(m.id)
                    }
                    if isStreaming {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
}
