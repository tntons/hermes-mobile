//
//  MessageCell.swift
//  Hermes
//

import SwiftUI

/// One row in the conversation. Lays out per role:
///   .user     — solid bubble, trailing-anchored, with copy / edit / retry.
///   .assistant — leading Hermes mark + transparent text, animated reasoning
///                 (Thought for Ns), tool cards, terminal badge (only on
///                 the last message of a turn).
///   .system / .tool — centered, captioned, gray.
struct MessageCell: View {
    let message: ChatMessage
    let isStreaming: Bool
    var isLastInTurn: Bool = false
    var isLatestResponse: Bool = false
    let onRegenerate: () -> Void

    private static let bubbleCornerRadius: CGFloat = 18

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 48)
                userBubble
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                avatar(symbol: "sparkles", tint: HermesTheme.accent, fill: true)
                VStack(alignment: .leading, spacing: 10) {
                    if isStreaming,
                       message.text.isEmpty,
                       message.reasoning.isEmpty,
                       message.pendingTool == nil,
                       message.toolCalls.isEmpty {
                        HermesActivityIndicator(
                            label: "Hermes is thinking…",
                            detail: "Preparing a response"
                        )
                    }
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
                        if isStreaming {
                            HermesActivityIndicator(label: "Generating response…", systemImage: "text.bubble")
                        }
                        if isLastInTurn, message.isFinal {
                            responseActions
                        }
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
                    .foregroundStyle(HermesTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var responseActions: some View {
        HStack(spacing: HermesTheme.Spacing.sm) {
            Button {
                UIPasteboard.general.string = message.text
                HapticManager.play(.soft)
                withAnimation(.easeInOut(duration: 0.15)) {
                    copiedResponse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copiedResponse = false
                    }
                }
            } label: {
                Label(copiedResponse ? "Copied" : "Copy", systemImage: copiedResponse ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(HermesTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy response")

            if isLatestResponse {
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(HermesTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
                .accessibilityLabel("Regenerate response")
            }
        }
        .padding(.top, 2)
    }

    // MARK: - User bubble

    @ViewBuilder
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(HermesTheme.textPrimary)
                // No .textSelection here — text selection adds 3 gesture
                // recognizers (UITapGestureRecognizer, UILongPressGestureRecognizer,
                // UIPanGestureRecognizer) that compete with the nav bar back
                // button when the user bubble is scrolled near the top of the
                // ScrollView. User messages don't need inline selection; copy
                // is handled via the confirmationDialog below.
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(HermesTheme.userBubble, in: asymmetricBubble)
            HStack(spacing: 6) {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(HermesTheme.textTertiary)
                Button {
                    userMenuShown = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundStyle(HermesTheme.textTertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
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
    @State private var copiedResponse: Bool = false

    // MARK: - Avatar

    @ViewBuilder
    private func avatar(symbol: String, tint: Color, fill: Bool) -> some View {
        ZStack {
            Circle()
                .fill(fill ? HermesTheme.accentSoft.opacity(0.52) : HermesTheme.surfaceElevated)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - ReasoningCard

struct ReasoningCard: View {
    let text: String
    let isStreaming: Bool
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isStreaming {
                    PulsingDot()
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(HermesTheme.textSecondary)
                }
                Text(isStreaming ? "Thinking…" : "Thought for \(estimatedSeconds)s")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HermesTheme.textSecondary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HermesTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            if expanded {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(HermesTheme.textSecondary)
                    // No .textSelection here — same gesture-recognizer
                    // rationale as the user bubble. Reasoning text is rarely
                    // at scroll position 0 (the user's own messages push it
                    // down), but removing it costs nothing and removes one
                    // more potential tap-eater.
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
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
                    .fill(HermesTheme.textSecondary)
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
                        HermesBouncingProgressLabel()
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
                        .foregroundStyle(isRunning ? HermesTheme.accent : HermesTheme.textSecondary)
                    Spacer(minLength: 4)
                    if let d = duration {
                        Text(String(format: "%.1fs", d))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(HermesTheme.textTertiary)
                    }
                    if hasExpandableContent {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(HermesTheme.textTertiary)
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
                            .foregroundStyle(HermesTheme.textTertiary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = preview ?? args?.preview ?? ""
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(HermesTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)

                    ScrollView {
                        Text(preview ?? args?.preview ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(HermesTheme.textSecondary)
                            // No .textSelection here — the expanded tool
                            // output has its own copy button (the header
                            // row above), and the scrollview's text would
                            // otherwise add 3 more gesture recognizers that
                            // could compete with the nav bar.
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
        if isRunning { return "Working · \(humanName)" }
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
            HStack(spacing: HermesTheme.Spacing.xs) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text("Approval required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HermesTheme.textPrimary)
                Spacer()
                Text("ACTION")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.orange)
            }
            Text(approval.command)
                .font(.callout.monospaced())
                .padding(8)
                .background(HermesTheme.surfaceElevated, in: .rect(cornerRadius: 6))
                // No .textSelection — approval commands are short, the
                // user copies via the system share/select-all if needed.
                .lineLimit(3)
                .truncationMode(.tail)
            Text(approval.description)
                .font(.caption)
                .foregroundStyle(HermesTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Text("Review this command before choosing how Hermes should proceed.")
                .font(.caption)
                .foregroundStyle(HermesTheme.textTertiary)
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
        .background(HermesTheme.surface, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.75)
        }
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
                Text("Finished").font(.caption).foregroundStyle(HermesTheme.textSecondary)
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(HermesTheme.textSecondary)
                Text("Cancelled").font(.caption).foregroundStyle(HermesTheme.textSecondary)
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
