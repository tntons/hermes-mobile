//
//  MessageCell.swift
//  Hermes
//

import SwiftUI

/// One row in the conversation. Lays out per role:
///   .user     — solid bubble, trailing-anchored, with copy / edit / retry.
///   .assistant — leading avatar + transparent text, animated reasoning
///                 (Thought for Ns), tool cards, terminal badge (only on
///                 the last message of a turn).
///   .system / .tool — centered, captioned, gray.
struct MessageCell: View {
    let message: ChatMessage
    let isStreaming: Bool
    var isLastInTurn: Bool = false

    private static let bubbleCornerRadius: CGFloat = 18

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 48)
                userBubble
                avatar(symbol: "person.fill", tint: .secondary, fill: false)
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                avatar(symbol: "sparkles", tint: .accentColor, fill: true)
                VStack(alignment: .leading, spacing: 10) {
                    if !message.reasoning.isEmpty {
                        ReasoningCard(text: message.reasoning, isStreaming: isStreaming && message.text.isEmpty)
                    }
                    if let pending = message.pendingTool {
                        ToolCallCard(name: pending.name, args: pending.args, preview: pending.preview, isRunning: true)
                    }
                    ForEach(Array(message.toolCalls.enumerated()), id: \.offset) { _, t in
                        ToolCallCard(name: t.name, args: t.args, preview: t.preview, isRunning: false, isError: t.is_error)
                    }
                    if !message.text.isEmpty {
                        HeightAwareMarkdown(text: message.text, isStreaming: !message.isFinal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if let a = message.approval { ApprovalCard(approval: a) }
                    if isLastInTurn, let t = message.terminal, message.isFinal {
                        TerminalBadge(state: t)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .system, .tool:
            HStack {
                Spacer()
                Text(message.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }

    // MARK: - User bubble

    @ViewBuilder
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.accentColor, in: asymmetricBubble)
                // .contextMenu { userMenu }  ← moved off the bubble background.
                // Attaching .contextMenu to the bubble's background modifier
                // made the gesture recognizer's hit area extend across the
                // full row, which then intercepted taps intended for the nav
                // bar's back chevron when the message was scrolled near the top.
                .onLongPressGesture(minimumDuration: 0.5) {
                    userMenuShown = true
                }
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)
        }
        .confirmationDialog("Message actions", isPresented: $userMenuShown, titleVisibility: .hidden) {
            Button("Copy") { UIPasteboard.general.string = message.text }
            Button("Edit") { UIPasteboard.general.string = message.text }
            Button("Retry", role: .destructive) { /* wired in v2 */ }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var asymmetricBubble: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.bubbleCornerRadius,
            bottomLeadingRadius: Self.bubbleCornerRadius,
            bottomTrailingRadius: 4,
            topTrailingRadius: Self.bubbleCornerRadius
        )
    }

    @ViewBuilder
    private var userMenu: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            // Edit-and-resend: caller passes this via a closure in v2.
            // For now we just copy to clipboard as a placeholder so the
            // menu works without crashing on dev builds.
            UIPasteboard.general.string = message.text
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            // Retry hook — wired in v2.
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
        }
    }

    @State private var userMenuShown: Bool = false

    // MARK: - Avatar

    @ViewBuilder
    private func avatar(symbol: String, tint: Color, fill: Bool) -> some View {
        ZStack {
            Circle()
                .fill(fill ? tint.opacity(0.18) : Color.secondary.opacity(0.10))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - ReasoningCard

struct ReasoningCard: View {
    let text: String
    let isStreaming: Bool
    @State private var expanded: Bool = false

    private var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isStreaming {
                    PulsingDot()
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Thought for \(estimatedSeconds)s")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if expanded {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private var estimatedSeconds: Int {
        // Cheap heuristic — words / ~3 wps. Better than "0s" when the model
        // streams reasoning text.
        max(1, text.split(separator: " ").count / 3)
    }
}

// MARK: - PulsingDot

private struct PulsingDot: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.25)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}

// MARK: - ToolCallCard

struct ToolCallCard: View {
    let name: String
    let args: AnyCodable?
    let preview: String?
    let isRunning: Bool
    var isError: Bool? = nil
    @State private var previewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.tint)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let p = preview, !p.isEmpty, previewExpanded {
                        Text(p)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 4)
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else if isError == true {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let p = preview, !p.isEmpty {
                Button {
                    withAnimation(.snappy) { previewExpanded.toggle() }
                } label: {
                    Text(previewExpanded ? "Hide preview" : "Show preview")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            if let a = args, !a.preview.isEmpty {
                DisclosureGroup("Args") {
                    Text(a.preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke((isError == true ? Color.red : Color.secondary).opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private var iconName: String {
        switch name.lowercased() {
        case "bash", "shell", "command": return "terminal"
        case "read", "edit", "file", "write": return "doc.text"
        case "search", "grep", "rg": return "magnifyingglass"
        case "web", "fetch", "http": return "globe"
        case "compress": return "rectangle.compress.vertical"
        default: return "wrench.adjustable"
        }
    }
}

// MARK: - Approval

struct ApprovalCard: View {
    let approval: SSEEvent.ApprovalEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hermes asks for approval", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
            Text(approval.command)
                .font(.callout.monospaced())
                .padding(8)
                .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 6))
                .textSelection(.enabled)
            Text(approval.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                ForEach(approval.choices, id: \.self) { choice in
                    Button(choice.capitalized) {
                        // v1: tap is logged but not wired to /api/approval/respond.
                        // Phase 5 will add a real POST.
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.10), in: .rect(cornerRadius: 12))
    }
}

// MARK: - Terminal

struct TerminalBadge: View {
    let state: TerminalState
    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .success:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Complete").font(.caption).foregroundStyle(.secondary)
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(.secondary)
                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(m).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.top, 2)
    }
}
