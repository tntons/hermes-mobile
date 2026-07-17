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
                        ToolCallCard(name: t.name, args: t.args, preview: t.preview, isRunning: false, isError: t.is_error, duration: t.duration)
                    }
                    if !message.text.isEmpty {
                        MarkdownText(text: message.text)
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
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .modifier(Pulse(delay: Double(i) * 0.18))
            }
        }
    }
}

private struct Pulse: ViewModifier {
    let delay: Double
    @State private var scale: CGFloat = 0.7
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(scale < 1.0 ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    scale = 1.3
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
    var duration: Double? = nil
    @State private var expanded: Bool = false
    @State private var fullyExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible. Mirrors the Hermes Desktop's
            // collapsed-state (no card fill, no border, just a line of text).
            Button {
                guard hasExpandableContent else { return }
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView().controlSize(.mini)
                    } else if isError == true {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Image(systemName: iconName)
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                    Text(titleText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let d = duration {
                        Text(String(format: "%.1fs", d))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if hasExpandableContent {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(.rect)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .disabled(!hasExpandableContent)

            if expanded, hasExpandableContent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("OUTPUT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = preview ?? args?.preview ?? ""
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)

                    ScrollView {
                        Text(preview ?? args?.preview ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(fullyExpanded ? nil : 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)

                    if let preview = preview, preview.count > 200, !fullyExpanded {
                        Button {
                            withAnimation(.snappy) { fullyExpanded = true }
                        } label: {
                            Text("Show more")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(0.85)
    }

    private var hasExpandableContent: Bool {
        let previewNonEmpty = (preview?.isEmpty == false)
        let argsNonEmpty = (args?.preview.isEmpty == false)
        return previewNonEmpty || argsNonEmpty
    }

    private var titleText: String {
        if isError == true { return "Tool error: \(name)" }
        if isRunning { return "Running \(humanName)" }
        return humanName
    }

    private var humanName: String {
        let n = name.lowercased()
        switch n {
        case "bash", "shell", "command", "execute_code": return "command"
        case "read_file", "read": return "file"
        case "edit_file", "write_file": return "edit"
        case "patch": return "patch"
        case "search_files", "search", "rg", "grep": return "search"
        case "web_search", "web_extract": return "web search"
        case "web", "fetch", "http": return "fetch"
        case "list_files": return "list files"
        case "clarify": return "question"
        case "compress": return "compression"
        default: return name
        }
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
                .lineLimit(3)
                .truncationMode(.tail)
            Text(approval.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
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
                Text(m)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.top, 2)
    }
}
