//
//  ChatMessage.swift
//  JARVIS
//
//  UI-facing message model wrapping a `Message` plus its transient streaming state.
//

import Foundation

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var role: Message.Role
    public var text: String                       // accumulated streamed text
    public var reasoning: String                  // accumulated reasoning text
    public var toolCalls: [ToolCall]              // native tool-call cards
    public var pendingTool: ToolCall?             // currently in-progress tool
    public var approval: SSEEvent.ApprovalEvent?
    public var terminal: TerminalState?
    public var timestamp: Date
    public var isFinal: Bool

    public init(
        id: UUID = UUID(),
        role: Message.Role,
        text: String = "",
        reasoning: String = "",
        toolCalls: [ToolCall] = [],
        pendingTool: ToolCall? = nil,
        approval: SSEEvent.ApprovalEvent? = nil,
        terminal: TerminalState? = nil,
        timestamp: Date = .now,
        isFinal: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.pendingTool = pendingTool
        self.approval = approval
        self.terminal = terminal
        self.timestamp = timestamp
        self.isFinal = isFinal
    }

    /// Build a user chat message from raw text.
    public static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text, terminal: .success, isFinal: true)
    }

    /// Build an assistant chat message placeholder (will stream into it).
    public static func assistant() -> ChatMessage {
        ChatMessage(role: .assistant)
    }

    /// Append a token delta to the assistant text.
    public mutating func append(token delta: String) {
        guard !delta.isEmpty else { return }
        text.append(delta)
    }

    public mutating func append(reasoning delta: String) {
        guard !delta.isEmpty else { return }
        reasoning.append(delta)
    }
}
