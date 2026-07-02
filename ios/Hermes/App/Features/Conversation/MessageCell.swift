//
//  MessageCell.swift
//  Hermes
//

import SwiftUI

struct MessageCell: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer()
                Bubble(role: .user) {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.reasoning.isEmpty {
                    ReasoningBubble(text: message.reasoning)
                }
                if let pending = message.pendingTool {
                    ToolCallCard(name: pending.name, args: pending.args, preview: pending.preview, isRunning: true)
                }
                ForEach(Array(message.toolCalls.enumerated()), id: \.offset) { _, t in
                    ToolCallCard(name: t.name, args: t.args, preview: t.preview, isRunning: false, isError: t.is_error)
                }
                if !message.text.isEmpty {
                    HeightAwareMarkdown(text: message.text, isStreaming: !message.isFinal)
                }
                if let a = message.approval {
                    ApprovalCard(approval: a)
                }
                if let t = message.terminal, message.isFinal {
                    TerminalBadge(state: t)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system, .tool:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Bubble

enum BubbleRole { case user, assistant }
struct Bubble<Content: View>: View {
    let role: BubbleRole
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                        in: .rect(cornerRadius: 14))
    }
}

// MARK: - Reasoning

struct ReasoningBubble: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Thinking", isExpanded: $expanded) {
            Text(text)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
        .font(.subheadline.bold())
    }
}

// MARK: - Tool card

struct ToolCallCard: View {
    let name: String
    let args: AnyCodable?
    let preview: String?
    let isRunning: Bool
    var isError: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isRunning { ProgressView().controlSize(.mini) }
                else if isError == true {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            if let p = preview, !p.isEmpty {
                Text(p)
                    .font(.caption.monospaced())
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
            if let a = args {
                DisclosureGroup("Args") {
                    Text(a.preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke((isError == true ? Color.red.opacity(0.3) : Color.secondary.opacity(0.2)), lineWidth: 1)
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
        .padding(10)
        .background(Color.yellow.opacity(0.10), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Terminal

struct TerminalBadge: View {
    let state: TerminalState
    var body: some View {
        HStack(spacing: 4) {
            switch state {
            case .success:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Complete").font(.caption)
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(.secondary)
                Text("Cancelled").font(.caption)
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(m).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
